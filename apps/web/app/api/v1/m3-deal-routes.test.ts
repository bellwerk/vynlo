import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { DELETE as releaseInventory } from "./deals/[id]/inventory-units/[inventoryLinkId]/route";
import { GET as getDeal } from "./deals/[id]/route";
import {
  GET as listLineItems,
  POST as addLineItem,
} from "./deals/[id]/line-items/route";
import { POST as createTradeIn } from "./deals/[id]/trade-ins/route";
import { POST as transitionDeal } from "./deals/[id]/transition/route";
import { GET as listDeals, POST as createDeal } from "./deals/route";
import { PATCH as updateLineItem } from "./deal-line-items/[id]/route";
import { POST as confirmTradeInInventory } from "./trade-ins/[id]/confirm-inventory/route";

const WORKSPACE_ID = "10000000-0000-4000-8000-000000000001";
const DEAL_ID = "20000000-0000-4000-8000-000000000001";
const CHILD_ID = "30000000-0000-4000-8000-000000000001";
const LOCATION_ID = "40000000-0000-4000-8000-000000000001";
const LEGAL_ENTITY_ID = "50000000-0000-4000-8000-000000000001";
const OWNER_ID = "60000000-0000-4000-8000-000000000001";
const AUDIT_ID = "70000000-0000-4000-8000-000000000001";
const OUTBOX_ID = "80000000-0000-4000-8000-000000000001";
const CORRELATION_ID = "90000000-0000-4000-8000-000000000001";

function request(path: string, body?: unknown, method = "POST"): Request {
  return new Request(`http://localhost${path}`, {
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    headers: {
      Authorization: "Bearer header.payload.signature",
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      ...(method === "GET" ? {} : { "Idempotency-Key": "m3-deal-route-0001" }),
      "X-Correlation-Id": CORRELATION_ID,
      "X-Request-Id": "m3-deal-route-request-0001",
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
      canonical_status: "draft",
      deal_id: DEAL_ID,
      outbox_event_id: OUTBOX_ID,
      replayed: false,
      state_key: "draft",
      ...extra,
    },
  ];
}

describe("T-DEAL-001 / T-DEAL-002 / T-API-001 M3 deal routes", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv(
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
      "sb_publishable_public_project_key_material",
    );
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("creates a configured deal from header-derived workspace context", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(evidence({})),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createDeal(
      request("/api/v1/deals", {
        currencyCode: "CAD",
        dealTypeKey: "retail.cash",
        legalEntityId: LEGAL_ENTITY_ID,
        locationId: LOCATION_ID,
        notes: null,
        originatingLeadId: null,
        ownerMembershipId: OWNER_ID,
      }),
    );

    expect(response.status).toBe(201);
    const parameters = JSON.parse(
      String(fetchImplementation.mock.calls[0]?.[1]?.body),
    );
    expect(parameters).toMatchObject({
      p_deal_type_key: "retail.cash",
      p_idempotency_key: "m3-deal-route-0001",
      p_workspace_id: WORKSPACE_ID,
    });
    expect(parameters).not.toHaveProperty("workspaceId");
  });

  it("bounds filters and cursor values before listing", async () => {
    const updatedAt = "2026-07-16T12:00:00Z";
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          active_inventory_count: 1,
          active_line_item_count: 2,
          active_participant_count: 1,
          aggregate_version: 3,
          canonical_status: "active",
          currency_code: "CAD",
          deal_id: DEAL_ID,
          deal_type_key: "retail.cash",
          deal_type_labels: { en: "Cash retail", fr: "Vente comptant" },
          deal_type_version_id: CHILD_ID,
          legal_entity_id: LEGAL_ENTITY_ID,
          lifecycle_status: "active",
          location_id: LOCATION_ID,
          notes: null,
          originating_lead_id: null,
          owner_membership_id: OWNER_ID,
          state_key: "preparing",
          updated_at: updatedAt,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await listDeals(
      request(
        `/api/v1/deals?status=active&limit=25&cursor_updated_at=${encodeURIComponent(updatedAt)}&cursor_id=${DEAL_ID}`,
        undefined,
        "GET",
      ),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: [{ dealId: DEAL_ID, canonicalStatus: "active" }],
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_cursor_id: DEAL_ID,
      p_limit: 25,
      p_status: "active",
    });
  });

  it("rejects unknown status filters without contacting storage", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await listDeals(
      request("/api/v1/deals?status=tenant_magic", undefined, "GET"),
    );

    expect(response.status).toBe(422);
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it("returns localized options from the deal's pinned configuration", async () => {
    const timestamp = "2026-07-16T12:00:00Z";
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          aggregate_version: 3,
          available_transitions: [],
          cancelled_at: null,
          canonical_status: "active",
          closed_reason: null,
          completed_at: null,
          created_at: timestamp,
          currency_code: "CAD",
          deal_id: DEAL_ID,
          deal_type_behavior_flags: {
            finance_mode: "none",
            money_mode: "one_time",
          },
          deal_type_checksum: "0".repeat(64),
          deal_type_definition_id: CHILD_ID,
          deal_type_field_schema: { required: ["buyer_party_id"] },
          deal_type_key: "retail.cash",
          deal_type_labels: { en: "Cash retail", fr: "Vente comptant" },
          deal_type_revision: 1,
          deal_type_source: "starter_pack",
          deal_type_version: "1.0.0",
          deal_type_version_id: CHILD_ID,
          effective_at: timestamp,
          inventory_role_options: [
            {
              key: "sold",
              labels: { en: "Sale vehicle", fr: "Véhicule vendu" },
            },
          ],
          legal_entity_id: LEGAL_ENTITY_ID,
          lifecycle_status: "active",
          location_id: LOCATION_ID,
          notes: null,
          one_time_event_type_options: [
            { key: "deposit", labels: { en: "Deposit", fr: "Dépôt" } },
          ],
          originating_lead_id: null,
          owner_membership_id: OWNER_ID,
          participant_role_options: [
            { key: "buyer", labels: { en: "Buyer", fr: "Acheteur" } },
          ],
          state_key: "preparing",
          updated_at: timestamp,
          workflow_instance_id: CHILD_ID,
          workflow_version_id: CHILD_ID,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await getDeal(
      request(`/api/v1/deals/${DEAL_ID}`, undefined, "GET"),
      { params: Promise.resolve({ id: DEAL_ID }) },
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        dealId: DEAL_ID,
        inventoryRoleOptions: [{ key: "sold" }],
        oneTimeEventTypeOptions: [{ key: "deposit" }],
        participantRoleOptions: [{ key: "buyer" }],
      },
    });
  });

  it("transitions with aggregate version and configured key", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(evidence({ workflow_event_id: CHILD_ID })),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await transitionDeal(
      request(`/api/v1/deals/${DEAL_ID}/transition`, {
        expectedVersion: 3,
        reason: "Synthetic acceptance",
        transitionKey: "confirm",
      }),
      { params: Promise.resolve({ id: DEAL_ID }) },
    );

    expect(response.status).toBe(200);
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_deal_id: DEAL_ID,
      p_expected_version: 3,
      p_transition_key: "confirm",
    });
  });

  it("adds exact line-item values without number conversion", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(evidence({ line_item_id: CHILD_ID })),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await addLineItem(
      request(`/api/v1/deals/${DEAL_ID}/line-items`, {
        expectedVersion: 3,
        itemType: "vehicle",
        key: "sale_vehicle",
        label: "Vehicle",
        paymentTimingKey: null,
        quantity: "1.000000",
        sortOrder: 0,
        sourceKey: null,
        sourceReference: null,
        taxClassificationKey: null,
        unitAmount: { amountMinor: "2500000", currencyCode: "CAD" },
      }),
      { params: Promise.resolve({ id: DEAL_ID }) },
    );

    expect(response.status).toBe(201);
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_quantity: "1.000000",
      p_unit_amount_minor: "2500000",
    });
  });

  it("lists line items with a bounded sort cursor", async () => {
    const timestamp = "2026-07-16T12:00:00Z";
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          created_at: timestamp,
          created_by: OWNER_ID,
          currency_code: "CAD",
          item_type: "vehicle",
          key: "sale_vehicle",
          label: "Vehicle",
          line_item_id: CHILD_ID,
          payment_timing_key: null,
          quantity: "1.000000",
          released_at: null,
          released_by: null,
          sort_order: 1,
          source_key: null,
          source_reference: null,
          status: "active",
          tax_classification_key: null,
          unit_amount_minor: "2500000",
          updated_at: timestamp,
          updated_by: OWNER_ID,
          version: 1,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await listLineItems(
      request(
        `/api/v1/deals/${DEAL_ID}/line-items?limit=20&cursor_sort_order=0&cursor_id=${CHILD_ID}`,
        undefined,
        "GET",
      ),
      { params: Promise.resolve({ id: DEAL_ID }) },
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: [{ lineItemId: CHILD_ID, unitAmountMinor: "2500000" }],
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_cursor_id: CHILD_ID,
      p_cursor_sort_order: 0,
      p_deal_id: DEAL_ID,
      p_limit: 20,
    });
  });

  it("updates a line item by path id while verifying its deal id", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(evidence({ line_item_id: CHILD_ID, line_item_version: 2 })),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await updateLineItem(
      request(`/api/v1/deal-line-items/${CHILD_ID}`, {
        dealId: DEAL_ID,
        expectedLineItemVersion: 1,
        expectedVersion: 5,
        itemType: "vehicle",
        label: "Vehicle updated",
        paymentTimingKey: null,
        quantity: "1.000000",
        sortOrder: 1,
        sourceKey: null,
        sourceReference: null,
        taxClassificationKey: null,
        unitAmount: { amountMinor: "2600000", currencyCode: "CAD" },
      }),
      { params: Promise.resolve({ id: CHILD_ID }) },
    );

    expect(response.status).toBe(200);
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_deal_id: DEAL_ID,
      p_expected_line_item_version: 1,
      p_line_item_id: CHILD_ID,
      p_unit_amount_minor: "2600000",
    });
  });

  it("releases the exact inventory link and returns normative 204", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(evidence({ inventory_link_id: CHILD_ID })),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await releaseInventory(
      request(
        `/api/v1/deals/${DEAL_ID}/inventory-units/${CHILD_ID}`,
        { expectedVersion: 4 },
        "DELETE",
      ),
      {
        params: Promise.resolve({ id: DEAL_ID, inventoryLinkId: CHILD_ID }),
      },
    );

    expect(response.status).toBe(204);
    expect(await response.text()).toBe("");
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_deal_id: DEAL_ID,
      p_inventory_link_id: CHILD_ID,
    });
  });

  it("records a trade-in without implicitly creating inventory", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(evidence({ trade_in_id: CHILD_ID, trade_in_version: 1 })),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createTradeIn(
      request(`/api/v1/deals/${DEAL_ID}/trade-ins`, {
        allowance: { amountMinor: "250000", currencyCode: "CAD" },
        conditionKey: "used.good",
        enteredVehicleFacts: { make: "Synthetic", model: "Fixture" },
        expectedVersion: 5,
        lenderPartyId: null,
        lienAmount: { amountMinor: "0", currencyCode: "CAD" },
        odometerUnit: "km",
        odometerValue: 120000,
        ownerPartyId: OWNER_ID,
        payoffAmount: { amountMinor: "0", currencyCode: "CAD" },
        taxEligibilityInputs: { ownershipConfirmed: true },
        vehicleId: null,
      }),
      { params: Promise.resolve({ id: DEAL_ID }) },
    );

    expect(response.status).toBe(201);
    const parameters = JSON.parse(
      String(fetchImplementation.mock.calls[0]?.[1]?.body),
    );
    expect(parameters).toMatchObject({
      p_allowance_minor: "250000",
      p_deal_id: DEAL_ID,
      p_expected_version: 5,
    });
    expect(parameters).not.toHaveProperty("p_inventory_unit_id");
  });

  it("confirms resulting inventory through a separate explicit command", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(evidence({ trade_in_id: CHILD_ID, trade_in_version: 2 })),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await confirmTradeInInventory(
      request(`/api/v1/trade-ins/${CHILD_ID}/confirm-inventory`, {
        expectedTradeInVersion: 1,
        expectedVersion: 6,
        inventoryUnitId: LOCATION_ID,
      }),
      { params: Promise.resolve({ id: CHILD_ID }) },
    );

    expect(response.status).toBe(200);
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_expected_trade_in_version: 1,
      p_inventory_unit_id: LOCATION_ID,
      p_trade_in_id: CHILD_ID,
    });
  });
});
