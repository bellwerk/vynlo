import { describe, expect, it, vi } from "vitest";

import type { AuthenticatedRpcGateway } from "./vertical-slice-api";
import {
  M3ApplicationValidationError,
  M3CrmApplicationService,
  M3RpcContractError,
} from "./index";

const WORKSPACE_ID = "10000000-0000-4000-8000-000000000001";
const PARTY_ID = "20000000-0000-4000-8000-000000000001";
const CONTACT_ID = "30000000-0000-4000-8000-000000000001";
const IDENTIFIER_ID = "30000000-0000-4000-8000-000000000002";
const PREFERENCE_ID = "30000000-0000-4000-8000-000000000003";
const LEAD_ID = "40000000-0000-4000-8000-000000000001";
const DEAL_ID = "50000000-0000-4000-8000-000000000001";
const LOCATION_ID = "60000000-0000-4000-8000-000000000001";
const EVENT_ID = "70000000-0000-4000-8000-000000000001";
const AUDIT_ID = "80000000-0000-4000-8000-000000000001";
const OUTBOX_ID = "90000000-0000-4000-8000-000000000001";

function command(body: unknown) {
  return {
    body,
    metadata: {
      accessToken: "header.payload.signature",
      correlationId: "a0000000-0000-4000-8000-000000000001",
      idempotencyKey: "m3-command-0001",
      requestId: "m3-request-0001",
      workspaceId: WORKSPACE_ID,
    },
  };
}

function entityCommand(body: unknown, entityId: string) {
  return { ...command(body), entityId };
}

function evidence(extra: Record<string, unknown>) {
  return [
    {
      aggregate_version: 2,
      audit_event_id: AUDIT_ID,
      outbox_event_id: OUTBOX_ID,
      replayed: false,
      ...extra,
    },
  ];
}

function service(result: unknown) {
  const gateway: AuthenticatedRpcGateway = {
    invoke: vi.fn(async () => result),
  };
  return { application: new M3CrmApplicationService(gateway), gateway };
}

function partyDetailResult(
  partyType: "organization" | "person",
  profile: unknown,
) {
  return [
    {
      addresses: [],
      contacts: [],
      display_name: "Synthetic party",
      identifiers: [],
      party_id: PARTY_ID,
      party_type: partyType,
      preferences: [],
      preferred_locale: "en",
      profile,
      relationships: [],
      status: "active",
      version: 1,
    },
  ];
}

describe("T-CRM-001 / T-API-001 party application contracts", () => {
  it("creates a typed person profile with actor command metadata", async () => {
    const { application, gateway } = service(evidence({ party_id: PARTY_ID }));

    await expect(
      application.createParty(
        command({
          partyType: "person",
          displayName: "Alex Example",
          preferredLocale: "fr",
          person: {
            birthDate: "1990-02-03",
            familyName: "Example",
            givenName: "Alex",
            preferredName: null,
          },
        }),
      ),
    ).resolves.toMatchObject({
      aggregateVersion: 2,
      partyId: PARTY_ID,
      replayed: false,
    });

    expect(gateway.invoke).toHaveBeenCalledWith({
      accessToken: "header.payload.signature",
      functionName: "m3_create_party",
      parameters: expect.objectContaining({
        p_birth_date: "1990-02-03",
        p_idempotency_key: "m3-command-0001",
        p_legal_name: null,
        p_party_type: "person",
        p_workspace_id: WORKSPACE_ID,
      }),
    });
  });

  it("returns a bounded party detail with active relationships and preferences", async () => {
    const { application } = service([
      {
        addresses: [],
        contacts: [],
        display_name: "Alex Example",
        identifiers: [],
        party_id: PARTY_ID,
        party_type: "person",
        preferences: [
          {
            allowed: false,
            channelKey: "email.marketing",
            consentSource: "Synthetic opt-out",
            consentStatus: "withdrawn",
            doNotContact: true,
            preferenceId: PREFERENCE_ID,
            version: 1,
          },
        ],
        preferred_locale: "en",
        profile: {
          birthDate: null,
          familyName: "Example",
          givenName: "Alex",
          preferredName: null,
        },
        relationships: [
          {
            effectiveFrom: null,
            effectiveTo: null,
            relatedPartyId: "20000000-0000-4000-8000-000000000002",
            relationshipId: "30000000-0000-4000-8000-000000000004",
            relationshipType: "household.member",
            version: 1,
          },
        ],
        status: "active",
        version: 3,
      },
    ]);

    await expect(
      application.getParty({
        accessToken: "header.payload.signature",
        partyId: PARTY_ID,
        workspaceId: WORKSPACE_ID,
      }),
    ).resolves.toMatchObject({
      partyId: PARTY_ID,
      preferences: [{ channelKey: "email.marketing", doNotContact: true }],
      relationships: [{ relationshipType: "household.member" }],
    });
  });

  it.each([
    [
      "an undeclared profile field",
      partyDetailResult("person", {
        birthDate: null,
        familyName: "Example",
        givenName: "Alex",
        preferredName: null,
        privateNote: "must not cross the response contract",
      }),
    ],
    [
      "a profile shape that does not match the party type",
      partyDetailResult("person", {
        legalName: "Synthetic Organization",
        registrationName: null,
      }),
    ],
  ])("rejects %s returned by the party detail RPC", async (_case, result) => {
    const { application } = service(result);

    await expect(
      application.getParty({
        accessToken: "header.payload.signature",
        partyId: PARTY_ID,
        workspaceId: WORKSPACE_ID,
      }),
    ).rejects.toBeInstanceOf(M3RpcContractError);
  });

  it("normalizes a contact while preserving consent provenance", async () => {
    const { application, gateway } = service(
      evidence({ contact_id: CONTACT_ID, party_id: PARTY_ID }),
    );

    await application.addPartyContact(
      entityCommand(
        {
          contactType: "email",
          consentSource: "Website form",
          consentStatus: "granted",
          doNotContact: false,
          isPreferred: true,
          isPrimary: true,
          value: "Person@Example.COM",
        },
        PARTY_ID,
      ),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_add_party_contact",
        parameters: expect.objectContaining({
          p_consent_source: "Website form",
          p_party_id: PARTY_ID,
          p_value: "Person@Example.COM",
        }),
      }),
    );
  });

  it("rejects an identifier without a reason before it reaches storage", async () => {
    const { application, gateway } = service([]);

    await expect(
      application.replacePartyIdentifier(
        entityCommand(
          {
            effectiveFrom: null,
            effectiveTo: null,
            identifierType: "driver_license",
            jurisdiction: "CA-QC",
            reason: "",
            value: "SYNTHETIC-ONLY",
          },
          PARTY_ID,
        ),
      ),
    ).rejects.toBeInstanceOf(M3ApplicationValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });

  it("updates the path-scoped party with an optimistic typed profile", async () => {
    const { application, gateway } = service(evidence({ party_id: PARTY_ID }));

    await application.updateParty(
      entityCommand(
        {
          displayName: "Alex Updated",
          expectedVersion: 4,
          partyType: "person",
          person: {
            birthDate: "1990-02-03",
            familyName: "Updated",
            givenName: "Alex",
            preferredName: null,
          },
          preferredLocale: "en",
        },
        PARTY_ID,
      ),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_update_party",
        parameters: expect.objectContaining({
          p_expected_version: 4,
          p_legal_name: null,
          p_party_id: PARTY_ID,
        }),
      }),
    );
  });

  it("preserves communication-consent provenance and rejects contradictions", async () => {
    const { application, gateway } = service(
      evidence({ party_id: PARTY_ID, preference_id: PREFERENCE_ID }),
    );

    await expect(
      application.setPartyCommunicationPreference(
        entityCommand(
          {
            allowed: true,
            channelKey: "email.marketing",
            consentSource: "Signed synthetic form",
            consentStatus: "granted",
            doNotContact: false,
            expectedVersion: 5,
          },
          PARTY_ID,
        ),
      ),
    ).resolves.toMatchObject({
      partyId: PARTY_ID,
      preferenceId: PREFERENCE_ID,
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_set_party_communication_preference",
        parameters: expect.objectContaining({
          p_channel_key: "email.marketing",
          p_consent_source: "Signed synthetic form",
          p_expected_version: 5,
        }),
      }),
    );

    const invalid = service([]);
    await expect(
      invalid.application.setPartyCommunicationPreference(
        entityCommand(
          {
            allowed: true,
            channelKey: "sms",
            consentSource: null,
            consentStatus: "unknown",
            doNotContact: true,
            expectedVersion: 1,
          },
          PARTY_ID,
        ),
      ),
    ).rejects.toBeInstanceOf(M3ApplicationValidationError);
    expect(invalid.gateway.invoke).not.toHaveBeenCalled();
  });

  it("reveals a restricted identifier only when storage confirms both path ids", async () => {
    const { application, gateway } = service([
      {
        audit_event_id: AUDIT_ID,
        identifier_id: IDENTIFIER_ID,
        party_id: PARTY_ID,
        plaintext_value: "SYNTHETIC-IDENTIFIER",
      },
    ]);

    await expect(
      application.revealPartyIdentifier({
        ...entityCommand(
          { reason: "Verify synthetic registration paperwork" },
          PARTY_ID,
        ),
        childId: IDENTIFIER_ID,
      }),
    ).resolves.toMatchObject({
      auditEventId: AUDIT_ID,
      identifierId: IDENTIFIER_ID,
      partyId: PARTY_ID,
      value: "SYNTHETIC-IDENTIFIER",
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_reveal_party_identifier",
        parameters: expect.objectContaining({
          p_identifier_id: IDENTIFIER_ID,
          p_reason: "Verify synthetic registration paperwork",
        }),
      }),
    );

    const mismatched = service([
      {
        audit_event_id: AUDIT_ID,
        identifier_id: IDENTIFIER_ID,
        party_id: "20000000-0000-4000-8000-000000000099",
        plaintext_value: "SYNTHETIC-IDENTIFIER",
      },
    ]);
    await expect(
      mismatched.application.revealPartyIdentifier({
        ...entityCommand({ reason: "Path ownership check" }, PARTY_ID),
        childId: IDENTIFIER_ID,
      }),
    ).rejects.toBeInstanceOf(M3RpcContractError);
  });
});

describe("T-CRM-001 / T-CRM-002 / T-API-001 lead application contracts", () => {
  it("creates a lead and accepts only strict command evidence", async () => {
    const { application, gateway } = service(
      evidence({
        lead_id: LEAD_ID,
        state_key: "new",
        workflow_event_id: EVENT_ID,
      }),
    );

    await expect(
      application.createLead(
        command({
          assigneeMembershipId: null,
          interestedInventoryUnitId: null,
          nextActionAt: "2026-07-17T14:00:00-04:00",
          prospectPartyId: PARTY_ID,
          sourceKey: "website",
          summary: "Synthetic web enquiry",
        }),
      ),
    ).resolves.toMatchObject({
      leadId: LEAD_ID,
      stateKey: "new",
      workflowEventId: EVENT_ID,
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({ functionName: "m3_create_lead" }),
    );
  });

  it("preserves expected-version and reason data for transitions", async () => {
    const { application, gateway } = service(
      evidence({
        lead_id: LEAD_ID,
        state_key: "lost",
        workflow_event_id: EVENT_ID,
      }),
    );

    await application.transitionLead(
      entityCommand(
        {
          expectedVersion: 3,
          reason: "Prospect deferred purchase",
          transitionKey: "lose",
        },
        LEAD_ID,
      ),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_transition_lead",
        parameters: expect.objectContaining({
          p_expected_version: 3,
          p_reason: "Prospect deferred purchase",
          p_transition_key: "lose",
        }),
      }),
    );
  });

  it("reads only configured available transition keys for a lead", async () => {
    const timestamp = "2026-07-16T12:00:00Z";
    const { application, gateway } = service([
      {
        assignee_membership_id: null,
        available_transitions: [
          {
            labels: { en: "Contacted", fr: "Contacté" },
            reasonRequired: false,
            toStateKey: "contacted",
            transitionKey: "new__contacted",
          },
        ],
        conversion_eligible: false,
        converted_deal_id: null,
        created_at: timestamp,
        interested_inventory_unit_id: null,
        lead_id: LEAD_ID,
        lost_reason: null,
        next_action_at: null,
        prospect_party_id: PARTY_ID,
        source_key: "website",
        state_key: "new",
        summary: "Synthetic web enquiry",
        version: 1,
        workflow_instance_id: EVENT_ID,
      },
    ]);

    await expect(
      application.getLead({
        accessToken: "header.payload.signature",
        leadId: LEAD_ID,
        workspaceId: WORKSPACE_ID,
      }),
    ).resolves.toMatchObject({
      availableTransitions: [
        {
          toStateKey: "contacted",
          transitionKey: "new__contacted",
        },
      ],
      conversionEligible: false,
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({ functionName: "m3_get_lead" }),
    );
  });

  it("converts a qualified lead through one actor-idempotent command", async () => {
    const { application, gateway } = service(
      evidence({ deal_id: DEAL_ID, lead_id: LEAD_ID }),
    );

    await expect(
      application.convertLead(
        entityCommand(
          {
            currencyCode: "cad",
            dealTypeKey: "retail.cash",
            expectedVersion: 4,
            legalEntityId: null,
            locationId: LOCATION_ID,
            ownerMembershipId: null,
          },
          LEAD_ID,
        ),
      ),
    ).resolves.toMatchObject({ dealId: DEAL_ID, leadId: LEAD_ID });

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_convert_lead",
        parameters: expect.objectContaining({
          p_currency_code: "CAD",
          p_expected_version: 4,
          p_idempotency_key: "m3-command-0001",
        }),
      }),
    );
  });

  it("rejects over-broad or malformed storage rows", async () => {
    const { application } = service([
      {
        assignee_membership_id: null,
        created_at: "2026-07-16T12:00:00Z",
        lead_id: LEAD_ID,
        next_action_at: null,
        prospect_party_id: PARTY_ID,
        source_key: "website",
        state_key: "new",
        summary: "Synthetic",
        unexpected_sensitive_column: "must not cross the boundary",
        version: 1,
      },
    ]);

    await expect(
      application.listLeads({
        accessToken: "header.payload.signature",
        workspaceId: WORKSPACE_ID,
      }),
    ).rejects.toBeInstanceOf(M3RpcContractError);
  });
});

describe("M3-CRM-AC-003 / T-CRM-001 task and appointment lifecycle contracts", () => {
  it("cancels a task only with optimistic version and a reason", async () => {
    const { application, gateway } = service(
      evidence({ task_id: EVENT_ID, task_state: "cancelled" }),
    );

    await expect(
      application.cancelTask(
        entityCommand(
          { expectedVersion: 2, reason: "Prospect requested no follow-up" },
          EVENT_ID,
        ),
      ),
    ).resolves.toMatchObject({ taskId: EVENT_ID, taskState: "cancelled" });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_cancel_task",
        parameters: expect.objectContaining({
          p_expected_version: 2,
          p_reason: "Prospect requested no follow-up",
          p_task_id: EVENT_ID,
        }),
      }),
    );
  });

  it("creates an appointment with notes and records a completed outcome", async () => {
    const created = service(
      evidence({
        appointment_id: EVENT_ID,
        appointment_status: "scheduled",
      }),
    );
    await created.application.createAppointment(
      command({
        attendeePartyIds: [PARTY_ID],
        dealId: null,
        endsAt: "2026-07-20T10:30:00-04:00",
        leadId: LEAD_ID,
        locationId: LOCATION_ID,
        notes: "Synthetic appointment context",
        remoteDetails: null,
        startsAt: "2026-07-20T10:00:00-04:00",
        timezone: "America/Toronto",
        title: "Vehicle visit",
      }),
    );
    expect(created.gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_create_appointment",
        parameters: expect.objectContaining({
          p_notes: "Synthetic appointment context",
          p_timezone: "America/Toronto",
        }),
      }),
    );

    const transitioned = service(
      evidence({
        appointment_id: EVENT_ID,
        appointment_status: "completed",
      }),
    );
    await transitioned.application.transitionAppointment(
      entityCommand(
        {
          expectedVersion: 1,
          outcome: "Vehicle reviewed; follow-up requested",
          reason: null,
          targetStatus: "completed",
        },
        EVENT_ID,
      ),
    );
    expect(transitioned.gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_transition_appointment",
        parameters: expect.objectContaining({
          p_appointment_id: EVENT_ID,
          p_outcome: "Vehicle reviewed; follow-up requested",
          p_target_status: "completed",
        }),
      }),
    );
  });

  it("rejects terminal appointment transitions without provenance", async () => {
    const { application, gateway } = service([]);
    await expect(
      application.transitionAppointment(
        entityCommand(
          {
            expectedVersion: 1,
            outcome: null,
            reason: null,
            targetStatus: "no_show",
          },
          EVENT_ID,
        ),
      ),
    ).rejects.toBeInstanceOf(M3ApplicationValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });
});
