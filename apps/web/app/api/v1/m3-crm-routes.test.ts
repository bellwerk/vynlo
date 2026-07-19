import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { GET as listActivities } from "./activities/route";
import { POST as transitionAppointment } from "./appointments/[id]/transition/route";
import { POST as convertLead } from "./leads/[id]/convert/route";
import { POST as transitionLead } from "./leads/[id]/transition/route";
import { GET as listLeads, POST as createLead } from "./leads/route";
import { POST as replaceIdentifier } from "./parties/[id]/identifiers/route";
import { POST as revealIdentifier } from "./parties/[id]/identifiers/[identifierId]/reveal/route";
import { POST as setCommunicationPreference } from "./parties/[id]/communication-preferences/route";
import {
  DELETE as archiveParty,
  GET as getParty,
  PATCH as updateParty,
} from "./parties/[id]/route";
import { POST as completeTask } from "./tasks/[id]/complete/route";
import { POST as cancelTask } from "./tasks/[id]/cancel/route";

const WORKSPACE_ID = "10000000-0000-4000-8000-000000000001";
const PARTY_ID = "20000000-0000-4000-8000-000000000001";
const IDENTIFIER_ID = "20000000-0000-4000-8000-000000000002";
const PREFERENCE_ID = "20000000-0000-4000-8000-000000000003";
const LEAD_ID = "30000000-0000-4000-8000-000000000001";
const DEAL_ID = "40000000-0000-4000-8000-000000000001";
const LOCATION_ID = "50000000-0000-4000-8000-000000000001";
const EVENT_ID = "60000000-0000-4000-8000-000000000001";
const AUDIT_ID = "70000000-0000-4000-8000-000000000001";
const OUTBOX_ID = "80000000-0000-4000-8000-000000000001";
const CORRELATION_ID = "90000000-0000-4000-8000-000000000001";
const PUBLIC_KEY = "sb_publishable_public_project_key_material";

function request(path: string, body?: unknown, method = "POST"): Request {
  return new Request(`http://localhost${path}`, {
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    headers: {
      Authorization: "Bearer header.payload.signature",
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      ...(method === "GET"
        ? {}
        : { "Idempotency-Key": "m3-route-command-0001" }),
      "X-Correlation-Id": CORRELATION_ID,
      "X-Request-Id": "m3-route-request-0001",
      "X-Workspace-Id": WORKSPACE_ID,
    },
    method,
  });
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

describe("T-CRM-001 / T-CRM-002 / T-API-001 Milestone 3 CRM routes", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", PUBLIC_KEY);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("lists workspace leads through the strict authenticated RPC", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          assignee_membership_id: null,
          created_at: "2026-07-16T12:00:00Z",
          lead_id: LEAD_ID,
          next_action_at: null,
          prospect_party_id: PARTY_ID,
          source_key: "website",
          state_key: "new",
          summary: "Synthetic enquiry",
          version: 1,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await listLeads(
      request("/api/v1/leads", undefined, "GET"),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: [{ leadId: LEAD_ID, stateKey: "new" }],
    });
    expect(fetchImplementation.mock.calls[0]?.[0]).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/m3_list_leads",
    );
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toEqual({ p_workspace_id: WORKSPACE_ID });
  });

  it("creates a lead without trusting workspace authority in JSON", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(
        evidence({
          lead_id: LEAD_ID,
          state_key: "new",
          workflow_event_id: EVENT_ID,
        }),
      ),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createLead(
      request("/api/v1/leads", {
        assigneeMembershipId: null,
        interestedInventoryUnitId: null,
        nextActionAt: null,
        prospectPartyId: PARTY_ID,
        sourceKey: "website",
        summary: "Synthetic enquiry",
      }),
    );

    expect(response.status).toBe(201);
    const parameters = JSON.parse(
      String(fetchImplementation.mock.calls[0]?.[1]?.body),
    );
    expect(parameters).toMatchObject({
      p_idempotency_key: "m3-route-command-0001",
      p_prospect_party_id: PARTY_ID,
      p_workspace_id: WORKSPACE_ID,
    });
    expect(parameters).not.toHaveProperty("workspaceId");
  });

  it("fails closed without disclosing undeclared party profile fields", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          addresses: [],
          contacts: [],
          display_name: "Alex Example",
          identifiers: [],
          party_id: PARTY_ID,
          party_type: "person",
          preferences: [],
          preferred_locale: "en",
          profile: {
            birthDate: null,
            familyName: "Example",
            givenName: "Alex",
            internalNote: "must-not-cross-the-api-boundary",
            preferredName: null,
          },
          relationships: [],
          status: "active",
          version: 1,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await getParty(
      request(`/api/v1/parties/${PARTY_ID}`, undefined, "GET"),
      { params: Promise.resolve({ id: PARTY_ID }) },
    );
    const responseBody = await response.json();

    expect(response.status).toBe(503);
    expect(responseBody).toEqual({
      error: {
        code: "service_unavailable",
        message: "The command service is temporarily unavailable.",
      },
    });
    expect(JSON.stringify(responseBody)).not.toContain(
      "must-not-cross-the-api-boundary",
    );
  });

  it("executes a reasoned optimistic lead transition", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(
        evidence({
          lead_id: LEAD_ID,
          state_key: "lost",
          workflow_event_id: EVENT_ID,
        }),
      ),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await transitionLead(
      request(`/api/v1/leads/${LEAD_ID}/transition`, {
        expectedVersion: 3,
        reason: "Prospect postponed",
        transitionKey: "lose",
      }),
      { params: Promise.resolve({ id: LEAD_ID }) },
    );

    expect(response.status).toBe(200);
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_expected_version: 3,
      p_lead_id: LEAD_ID,
      p_reason: "Prospect postponed",
    });
  });

  it("converts one qualified lead through an actor-idempotent command", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(evidence({ deal_id: DEAL_ID, lead_id: LEAD_ID })),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await convertLead(
      request(`/api/v1/leads/${LEAD_ID}/convert`, {
        currencyCode: "CAD",
        dealTypeKey: "retail.cash",
        expectedVersion: 4,
        legalEntityId: null,
        locationId: LOCATION_ID,
        ownerMembershipId: null,
      }),
      { params: Promise.resolve({ id: LEAD_ID }) },
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toMatchObject({
      data: { dealId: DEAL_ID, leadId: LEAD_ID },
    });
  });

  it("rejects an unsafe identifier command before PostgREST", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await replaceIdentifier(
      request(`/api/v1/parties/${PARTY_ID}/identifiers`, {
        effectiveFrom: null,
        effectiveTo: null,
        identifierType: "driver_license",
        jurisdiction: "CA-QC",
        reason: "",
        value: "SYNTHETIC-ONLY",
      }),
      { params: Promise.resolve({ id: PARTY_ID }) },
    );

    expect(response.status).toBe(422);
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it("operates profile update, consent, and archive through path/header authority", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (input) => {
      const functionName = String(input).split("/").at(-1);
      return functionName === "m3_set_party_communication_preference"
        ? Response.json(
            evidence({ party_id: PARTY_ID, preference_id: PREFERENCE_ID }),
          )
        : Response.json(evidence({ party_id: PARTY_ID }));
    });
    vi.stubGlobal("fetch", fetchImplementation);

    const updateResponse = await updateParty(
      request(
        `/api/v1/parties/${PARTY_ID}`,
        {
          displayName: "Alex Updated",
          expectedVersion: 2,
          partyType: "person",
          person: {
            birthDate: null,
            familyName: "Updated",
            givenName: "Alex",
            preferredName: null,
          },
          preferredLocale: "fr",
        },
        "PATCH",
      ),
      { params: Promise.resolve({ id: PARTY_ID }) },
    );
    const preferenceResponse = await setCommunicationPreference(
      request(`/api/v1/parties/${PARTY_ID}/communication-preferences`, {
        allowed: false,
        channelKey: "email.marketing",
        consentSource: "Synthetic opt-out",
        consentStatus: "withdrawn",
        doNotContact: true,
        expectedVersion: 3,
      }),
      { params: Promise.resolve({ id: PARTY_ID }) },
    );
    const archiveResponse = await archiveParty(
      request(
        `/api/v1/parties/${PARTY_ID}`,
        { expectedVersion: 4, reason: "Synthetic duplicate party" },
        "DELETE",
      ),
      { params: Promise.resolve({ id: PARTY_ID }) },
    );

    expect(updateResponse.status).toBe(200);
    expect(preferenceResponse.status).toBe(201);
    expect(archiveResponse.status).toBe(200);
    expect(fetchImplementation.mock.calls).toHaveLength(3);
    for (const call of fetchImplementation.mock.calls) {
      const parameters = JSON.parse(String(call[1]?.body));
      expect(parameters).toMatchObject({
        p_party_id: PARTY_ID,
        p_workspace_id: WORKSPACE_ID,
      });
      expect(parameters).not.toHaveProperty("workspaceId");
    }
  });

  it("reveals one restricted identifier with reason and path ownership evidence", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          audit_event_id: AUDIT_ID,
          identifier_id: IDENTIFIER_ID,
          party_id: PARTY_ID,
          plaintext_value: "SYNTHETIC-IDENTIFIER",
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await revealIdentifier(
      request(
        `/api/v1/parties/${PARTY_ID}/identifiers/${IDENTIFIER_ID}/reveal`,
        { reason: "Verify synthetic registration paperwork" },
      ),
      {
        params: Promise.resolve({ id: PARTY_ID, identifierId: IDENTIFIER_ID }),
      },
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        auditEventId: AUDIT_ID,
        identifierId: IDENTIFIER_ID,
        partyId: PARTY_ID,
        value: "SYNTHETIC-IDENTIFIER",
      },
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_identifier_id: IDENTIFIER_ID,
      p_reason: "Verify synthetic registration paperwork",
      p_workspace_id: WORKSPACE_ID,
    });
  });

  it("bounds timeline queries and task completion to path/header context", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (input) =>
      String(input).endsWith("m3_list_crm_timeline")
        ? Response.json([])
        : Response.json(
            evidence({ task_id: EVENT_ID, task_state: "completed" }),
          ),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const timelineResponse = await listActivities(
      request(`/api/v1/activities?lead_id=${LEAD_ID}`, undefined, "GET"),
    );
    const taskResponse = await completeTask(
      request(`/api/v1/tasks/${EVENT_ID}/complete`, { expectedVersion: 1 }),
      { params: Promise.resolve({ id: EVENT_ID }) },
    );

    expect(timelineResponse.status).toBe(200);
    expect(taskResponse.status).toBe(200);
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({ p_lead_id: LEAD_ID, p_workspace_id: WORKSPACE_ID });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[1]?.[1]?.body)),
    ).toMatchObject({ p_task_id: EVENT_ID, p_workspace_id: WORKSPACE_ID });
  });

  it("routes reasoned task cancellation and appointment outcome without body authority", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (input) =>
      String(input).endsWith("m3_cancel_task")
        ? Response.json(
            evidence({ task_id: EVENT_ID, task_state: "cancelled" }),
          )
        : Response.json(
            evidence({
              appointment_id: EVENT_ID,
              appointment_status: "completed",
            }),
          ),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const taskResponse = await cancelTask(
      request(`/api/v1/tasks/${EVENT_ID}/cancel`, {
        expectedVersion: 2,
        reason: "Prospect requested no follow-up",
      }),
      { params: Promise.resolve({ id: EVENT_ID }) },
    );
    const appointmentResponse = await transitionAppointment(
      request(`/api/v1/appointments/${EVENT_ID}/transition`, {
        expectedVersion: 1,
        outcome: "Vehicle reviewed; follow-up requested",
        reason: null,
        targetStatus: "completed",
      }),
      { params: Promise.resolve({ id: EVENT_ID }) },
    );

    expect(taskResponse.status).toBe(200);
    expect(appointmentResponse.status).toBe(200);
    const taskParameters = JSON.parse(
      String(fetchImplementation.mock.calls[0]?.[1]?.body),
    );
    const appointmentParameters = JSON.parse(
      String(fetchImplementation.mock.calls[1]?.[1]?.body),
    );
    expect(taskParameters).toMatchObject({
      p_reason: "Prospect requested no follow-up",
      p_task_id: EVENT_ID,
      p_workspace_id: WORKSPACE_ID,
    });
    expect(appointmentParameters).toMatchObject({
      p_appointment_id: EVENT_ID,
      p_outcome: "Vehicle reviewed; follow-up requested",
      p_workspace_id: WORKSPACE_ID,
    });
    expect(appointmentParameters).not.toHaveProperty("workspaceId");
  });
});
