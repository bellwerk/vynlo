import { describe, expect, it } from "vitest";

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
  planLeadConversion,
} from "./m3-domain";

const PARTY_ID = "10000000-0000-4000-8000-000000000001";
const LEAD_ID = "20000000-0000-4000-8000-000000000001";
const DEAL_ID = "30000000-0000-4000-8000-000000000001";
const INVENTORY_ID = "40000000-0000-4000-8000-000000000001";
const MEMBERSHIP_ID = "50000000-0000-4000-8000-000000000001";
const LOCATION_ID = "60000000-0000-4000-8000-000000000001";

function expectCode(operation: () => unknown, code: string): void {
  expect(operation).toThrowError(M3CrmDomainError);
  try {
    operation();
  } catch (error) {
    expect(error).toMatchObject({ code });
  }
}

describe("M3-CRM-AC-001 party details", () => {
  it("normalizes email/phone values and preserves explicit consent", () => {
    expect(
      normalizePartyContactCommand({
        idempotencyKey: "party-contact-001",
        partyId: PARTY_ID,
        contactType: "email",
        value: " Person@Example.COM ",
        isPrimary: true,
        isPreferred: true,
        consentStatus: "granted",
        consentSource: "Web lead form",
        doNotContact: false,
      }),
    ).toMatchObject({
      normalizedValue: "person@example.com",
      consentStatus: "granted",
    });
    expect(
      normalizePartyContactCommand({
        idempotencyKey: "party-contact-002",
        partyId: PARTY_ID,
        contactType: "phone",
        value: "+1 (514) 555-0100",
        isPrimary: false,
        isPreferred: false,
        consentStatus: "unknown",
        consentSource: null,
        doNotContact: true,
      }).normalizedValue,
    ).toBe("+15145550100");
  });

  it("requires consent provenance and structured addresses", () => {
    expectCode(
      () =>
        normalizePartyContactCommand({
          idempotencyKey: "party-contact-001",
          partyId: PARTY_ID,
          contactType: "email",
          value: "person@example.com",
          isPrimary: true,
          isPreferred: true,
          consentStatus: "granted",
          consentSource: null,
          doNotContact: false,
        }),
      "invalid_contact",
    );
    expect(
      normalizePartyAddressCommand({
        partyId: PARTY_ID,
        addressType: "home",
        line1: "100 Synthetic Street",
        line2: null,
        locality: "Exampleville",
        region: "QC",
        postalCode: "H0H 0H0",
        countryCode: "ca",
        isPrimary: true,
      }),
    ).toMatchObject({ countryCode: "CA", locality: "Exampleville" });
  });
});

describe("M3-CRM-AC-002 / T-CRM-001 lead and work planning", () => {
  it("normalizes a lead and its append-only timeline activity", () => {
    const lead = normalizeLeadCreateCommand({
      idempotencyKey: "lead-create-001",
      prospectPartyId: PARTY_ID,
      sourceKey: "website.form",
      interestedInventoryUnitId: INVENTORY_ID,
      assigneeMembershipId: MEMBERSHIP_ID,
      summary: "  Interested   in the synthetic vehicle ",
      nextActionAt: "2026-07-17T09:00:00-04:00",
    });
    expect(lead).toMatchObject({
      sourceKey: "website.form",
      summary: "Interested in the synthetic vehicle",
      nextActionAt: "2026-07-17T13:00:00.000Z",
    });

    expect(
      normalizeActivityCommand({
        idempotencyKey: "activity-create-001",
        partyId: PARTY_ID,
        leadId: LEAD_ID,
        dealId: null,
        activityType: "call",
        channelKey: "phone",
        direction: "outbound",
        subject: "First contact",
        body: "Left a synthetic voicemail.",
        providerReference: null,
        occurredAt: "2026-07-16T16:00:00Z",
      }),
    ).toMatchObject({ activityType: "call", leadId: LEAD_ID });
  });

  it("validates task reminder ordering", () => {
    expect(
      normalizeTaskCommand({
        idempotencyKey: "task-create-001",
        partyId: PARTY_ID,
        leadId: LEAD_ID,
        dealId: null,
        assigneeMembershipId: MEMBERSHIP_ID,
        title: "Call back",
        description: null,
        priority: "high",
        dueAt: "2026-07-18T15:00:00Z",
        reminderAt: "2026-07-18T14:00:00Z",
      }),
    ).toMatchObject({ priority: "high" });
    expectCode(
      () =>
        normalizeTaskCommand({
          idempotencyKey: "task-create-001",
          partyId: PARTY_ID,
          leadId: LEAD_ID,
          dealId: null,
          assigneeMembershipId: MEMBERSHIP_ID,
          title: "Call back",
          description: null,
          priority: "high",
          dueAt: "2026-07-18T15:00:00Z",
          reminderAt: "2026-07-18T16:00:00Z",
        }),
      "invalid_task",
    );
  });

  it("requires an explicit timezone and valid appointment interval", () => {
    const appointment = normalizeAppointmentCommand({
      idempotencyKey: "appointment-create-001",
      leadId: LEAD_ID,
      dealId: null,
      title: "Vehicle visit",
      startsAt: "2026-07-20T10:00:00-04:00",
      endsAt: "2026-07-20T10:30:00-04:00",
      timezone: "America/Toronto",
      locationId: LOCATION_ID,
      remoteDetails: null,
      notes: "Synthetic appointment context",
      attendeePartyIds: [PARTY_ID],
    });
    expect(appointment).toMatchObject({
      startsAt: "2026-07-20T14:00:00.000Z",
      timezone: "America/Toronto",
    });
    expectCode(
      () =>
        normalizeAppointmentCommand({
          ...appointment,
          idempotencyKey: "appointment-create-002",
          startsAt: "2026-07-20T10:00:00Z",
          endsAt: "2026-07-20T09:00:00Z",
          timezone: "Not/AZone",
          attendeePartyIds: [PARTY_ID],
        }),
      "invalid_appointment",
    );
  });

  it("requires task cancellation reason and appointment outcome provenance", () => {
    expect(
      normalizeTaskCancellationCommand({
        expectedVersion: 2,
        reason: "Prospect requested no further follow-up",
      }),
    ).toEqual({
      expectedVersion: 2,
      reason: "Prospect requested no further follow-up",
    });
    expect(
      normalizeAppointmentTransitionCommand({
        expectedVersion: 3,
        outcome: "Vehicle reviewed; follow-up requested",
        reason: null,
        targetStatus: "completed",
      }),
    ).toMatchObject({ targetStatus: "completed" });
    expect(
      normalizeAppointmentTransitionCommand({
        expectedVersion: 3,
        outcome: null,
        reason: "Prospect did not attend",
        targetStatus: "no_show",
      }),
    ).toMatchObject({ targetStatus: "no_show" });
    expectCode(
      () =>
        normalizeAppointmentTransitionCommand({
          expectedVersion: 3,
          outcome: null,
          reason: null,
          targetStatus: "cancelled",
        }),
      "reason_required",
    );
  });
});

describe("M3-CRM-AC-004 / T-CRM-002 lead conversion", () => {
  it("plans one qualified conversion and represents exact replay", () => {
    expect(
      planLeadConversion({
        leadId: LEAD_ID,
        conversionEligible: true,
        currentVersion: 5,
        expectedVersion: 5,
        existingConvertedDealId: null,
        dealTypeKey: "cash_retail",
        currencyCode: "cad",
        idempotencyKey: "lead-convert-001",
      }),
    ).toEqual({
      leadId: LEAD_ID,
      dealTypeKey: "cash_retail",
      currencyCode: "CAD",
      idempotencyKey: "lead-convert-001",
      resultingLeadVersion: 6,
      replayDealId: null,
    });

    expect(
      planLeadConversion({
        leadId: LEAD_ID,
        conversionEligible: false,
        currentVersion: 6,
        expectedVersion: 5,
        existingConvertedDealId: DEAL_ID,
        dealTypeKey: "cash_retail",
        currencyCode: "CAD",
        idempotencyKey: "lead-convert-001",
      }),
    ).toMatchObject({ replayDealId: DEAL_ID, resultingLeadVersion: 6 });
  });

  it("rejects stale or configuration-ineligible first conversion", () => {
    expectCode(
      () =>
        planLeadConversion({
          leadId: LEAD_ID,
          conversionEligible: true,
          currentVersion: 5,
          expectedVersion: 4,
          existingConvertedDealId: null,
          dealTypeKey: "cash_retail",
          currencyCode: "CAD",
          idempotencyKey: "lead-convert-001",
        }),
      "lead_version_conflict",
    );
    expectCode(
      () =>
        planLeadConversion({
          leadId: LEAD_ID,
          conversionEligible: false,
          currentVersion: 5,
          expectedVersion: 5,
          existingConvertedDealId: null,
          dealTypeKey: "cash_retail",
          currencyCode: "CAD",
          idempotencyKey: "lead-convert-001",
        }),
      "invalid_lead_conversion",
    );
  });
});
