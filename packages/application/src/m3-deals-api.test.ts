import { describe, expect, it, vi } from "vitest";

import type { AuthenticatedRpcGateway } from "./vertical-slice-api";
import {
  M3ApplicationValidationError,
  M3DealsApplicationService,
  M3RpcContractError,
} from "./index";

const WORKSPACE_ID = "10000000-0000-4000-8000-000000000001";
const DEAL_ID = "20000000-0000-4000-8000-000000000001";
const CHILD_ID = "30000000-0000-4000-8000-000000000001";
const PARTY_ID = "40000000-0000-4000-8000-000000000001";
const LOCATION_ID = "50000000-0000-4000-8000-000000000001";
const LEGAL_ENTITY_ID = "60000000-0000-4000-8000-000000000001";
const OWNER_ID = "70000000-0000-4000-8000-000000000001";
const AUDIT_ID = "80000000-0000-4000-8000-000000000001";
const OUTBOX_ID = "90000000-0000-4000-8000-000000000001";

function command(body: unknown) {
  return {
    body,
    metadata: {
      accessToken: "header.payload.signature",
      correlationId: "a0000000-0000-4000-8000-000000000001",
      idempotencyKey: "m3-deal-command-0001",
      requestId: "m3-deal-request-0001",
      workspaceId: WORKSPACE_ID,
    },
  };
}

function entityCommand(body: unknown, entityId = DEAL_ID) {
  return { ...command(body), entityId };
}

function childCommand(body: unknown, childId = CHILD_ID) {
  return { ...entityCommand(body), childId };
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

function service(result: unknown) {
  const gateway: AuthenticatedRpcGateway = {
    invoke: vi.fn(async () => result),
  };
  return { application: new M3DealsApplicationService(gateway), gateway };
}

describe("T-DEAL-001 / T-API-001 deal application contracts", () => {
  it("creates a configured deal with its legal and workflow context", async () => {
    const { application, gateway } = service(evidence({}));

    await expect(
      application.createDeal(
        command({
          currencyCode: "cad",
          dealTypeKey: "retail.cash",
          legalEntityId: LEGAL_ENTITY_ID,
          locationId: LOCATION_ID,
          notes: "Synthetic cash deal",
          originatingLeadId: null,
          ownerMembershipId: OWNER_ID,
        }),
      ),
    ).resolves.toMatchObject({
      aggregateVersion: 2,
      canonicalStatus: "draft",
      dealId: DEAL_ID,
      replayed: false,
    });

    expect(gateway.invoke).toHaveBeenCalledWith({
      accessToken: "header.payload.signature",
      functionName: "m3_create_deal",
      parameters: expect.objectContaining({
        p_currency_code: "CAD",
        p_deal_type_key: "retail.cash",
        p_idempotency_key: "m3-deal-command-0001",
        p_legal_entity_id: LEGAL_ENTITY_ID,
        p_workspace_id: WORKSPACE_ID,
      }),
    });
  });

  it("updates only explicitly supplied deal fields with expected-version", async () => {
    const { application, gateway } = service(evidence({}));

    await application.updateDeal(
      entityCommand({ expectedVersion: 4, notes: null }),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_update_deal",
        parameters: expect.objectContaining({
          p_clear_notes: true,
          p_expected_version: 4,
          p_notes: null,
        }),
      }),
    );
  });

  it("preserves configured transition key and optional reason", async () => {
    const { application, gateway } = service(
      evidence({ workflow_event_id: CHILD_ID }),
    );

    await application.transitionDeal(
      entityCommand({
        expectedVersion: 3,
        reason: "Customer confirmed",
        transitionKey: "confirm",
      }),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_transition_deal",
        parameters: expect.objectContaining({
          p_expected_version: 3,
          p_reason: "Customer confirmed",
          p_transition_key: "confirm",
        }),
      }),
    );
  });

  it("lists bounded deal projections with a complete cursor", async () => {
    const updatedAt = "2026-07-16T12:00:00Z";
    const { application, gateway } = service([
      {
        active_inventory_count: 1,
        active_line_item_count: 2,
        active_participant_count: 1,
        aggregate_version: 4,
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
    ]);

    await expect(
      application.listDeals({
        accessToken: "header.payload.signature",
        cursorId: DEAL_ID,
        cursorUpdatedAt: updatedAt,
        limit: 25,
        workspaceId: WORKSPACE_ID,
      }),
    ).resolves.toMatchObject([{ dealId: DEAL_ID, activeLineItemCount: 2 }]);
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_list_deals",
        parameters: expect.objectContaining({ p_limit: 25 }),
      }),
    );
  });

  it("rejects an incomplete list cursor before storage", async () => {
    const { application, gateway } = service([]);

    await expect(
      application.listDeals({
        accessToken: "header.payload.signature",
        cursorId: DEAL_ID,
        workspaceId: WORKSPACE_ID,
      }),
    ).rejects.toBeInstanceOf(M3ApplicationValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });
});

describe("T-DEAL-001 / T-DEAL-002 bounded deal read contracts", () => {
  it("returns the immutable deal-type and workflow pins with the deal", async () => {
    const timestamp = "2026-07-16T12:00:00Z";
    const { application } = service([
      {
        aggregate_version: 4,
        available_transitions: [
          {
            labels: { en: "Ready", fr: "Prêt" },
            reasonRequired: false,
            toStateKey: "ready",
            transitionKey: "preparing__ready",
          },
        ],
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
        deal_type_field_schema: { required: ["buyer"] },
        deal_type_key: "retail.cash",
        deal_type_labels: { en: "Cash retail", fr: "Vente comptant" },
        deal_type_revision: 1,
        deal_type_source: "starter_pack",
        deal_type_version: "1.0.0",
        deal_type_version_id: CHILD_ID,
        effective_at: timestamp,
        legal_entity_id: LEGAL_ENTITY_ID,
        lifecycle_status: "active",
        location_id: LOCATION_ID,
        notes: null,
        one_time_event_type_options: [
          { key: "deposit", labels: { en: "Deposit", fr: "Dépôt" } },
          { key: "receipt", labels: { en: "Receipt", fr: "Encaissement" } },
        ],
        originating_lead_id: null,
        owner_membership_id: OWNER_ID,
        participant_role_options: [
          { key: "buyer", labels: { en: "Buyer", fr: "Acheteur" } },
          { key: "seller", labels: { en: "Seller", fr: "Vendeur" } },
        ],
        state_key: "preparing",
        inventory_role_options: [
          {
            key: "sold",
            labels: { en: "Sale vehicle", fr: "Véhicule vendu" },
          },
        ],
        updated_at: timestamp,
        workflow_instance_id: PARTY_ID,
        workflow_version_id: PARTY_ID,
      },
    ]);

    await expect(
      application.getDeal({
        accessToken: "header.payload.signature",
        dealId: DEAL_ID,
        workspaceId: WORKSPACE_ID,
      }),
    ).resolves.toMatchObject({
      dealId: DEAL_ID,
      dealTypeChecksum: "0".repeat(64),
      dealTypeVersion: "1.0.0",
      availableTransitions: [
        expect.objectContaining({ transitionKey: "preparing__ready" }),
      ],
      inventoryRoleOptions: [expect.objectContaining({ key: "sold" })],
      oneTimeEventTypeOptions: [
        expect.objectContaining({ key: "deposit" }),
        expect.objectContaining({ key: "receipt" }),
      ],
      participantRoleOptions: [
        expect.objectContaining({ key: "buyer" }),
        expect.objectContaining({ key: "seller" }),
      ],
      workflowVersionId: PARTY_ID,
    });
  });

  it("lists strict participant, inventory, and line-item projections", async () => {
    const timestamp = "2026-07-16T12:00:00Z";
    const gateway: AuthenticatedRpcGateway = {
      invoke: vi.fn(async (request) => {
        if (request.functionName === "m3_list_deal_participants") {
          return [
            {
              created_at: timestamp,
              created_by: OWNER_ID,
              is_primary: true,
              participant_id: CHILD_ID,
              party_display_name: "Synthetic buyer",
              party_id: PARTY_ID,
              released_at: null,
              released_by: null,
              role_key: "buyer",
              status: "active",
              version: 1,
            },
          ];
        }
        if (request.functionName === "m3_list_deal_inventory") {
          return [
            {
              amount_minor: "2500000",
              created_at: timestamp,
              created_by: OWNER_ID,
              currency_code: "CAD",
              inventory_link_id: CHILD_ID,
              inventory_status: "available",
              inventory_unit_id: LOCATION_ID,
              metadata: {},
              released_at: null,
              released_by: null,
              role_key: "sold",
              status: "active",
              stock_number: "SYN-0001",
              version: 1,
            },
          ];
        }
        return [
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
            sort_order: 0,
            source_key: null,
            source_reference: null,
            status: "active",
            tax_classification_key: null,
            unit_amount_minor: "2500000",
            updated_at: timestamp,
            updated_by: OWNER_ID,
            version: 1,
          },
        ];
      }),
    };
    const application = new M3DealsApplicationService(gateway);
    const input = {
      accessToken: "header.payload.signature",
      dealId: DEAL_ID,
      workspaceId: WORKSPACE_ID,
    };

    await expect(
      application.listDealParticipants(input),
    ).resolves.toMatchObject([{ partyId: PARTY_ID, roleKey: "buyer" }]);
    await expect(application.listDealInventory(input)).resolves.toMatchObject([
      { inventoryLinkId: CHILD_ID, stockNumber: "SYN-0001" },
    ]);
    await expect(application.listDealLineItems(input)).resolves.toMatchObject([
      { lineItemId: CHILD_ID, unitAmountMinor: "2500000" },
    ]);
  });

  it("rejects incomplete child cursors before storage", async () => {
    const { application, gateway } = service([]);

    await expect(
      application.listDealParticipants({
        accessToken: "header.payload.signature",
        cursorId: CHILD_ID,
        dealId: DEAL_ID,
        workspaceId: WORKSPACE_ID,
      }),
    ).rejects.toBeInstanceOf(M3ApplicationValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });
});

describe("T-DEAL-002 exact line-item and link contracts", () => {
  it("passes exact decimal quantity and signed minor units as strings", async () => {
    const { application, gateway } = service(
      evidence({ line_item_id: CHILD_ID }),
    );

    await application.addLineItem(
      entityCommand({
        expectedVersion: 4,
        itemType: "discount",
        key: "manager_discount",
        label: "Manager discount",
        paymentTimingKey: null,
        quantity: "1.250000",
        sortOrder: 20,
        sourceKey: null,
        sourceReference: null,
        taxClassificationKey: null,
        unitAmount: { amountMinor: "-12500", currencyCode: "cad" },
      }),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_add_deal_line_item",
        parameters: expect.objectContaining({
          p_quantity: "1.250000",
          p_unit_amount_minor: "-12500",
        }),
      }),
    );
  });

  it("rejects executable inventory metadata before storage", async () => {
    const { application, gateway } = service([]);

    await expect(
      application.addInventory(
        entityCommand({
          expectedVersion: 1,
          inventoryUnitId: CHILD_ID,
          metadata: { script: "fetch('https://example.test')" },
          money: null,
          roleKey: "sold",
        }),
      ),
    ).rejects.toBeInstanceOf(M3ApplicationValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });

  it("uses the link id rather than trusting an inventory unit id on release", async () => {
    const { application, gateway } = service(
      evidence({ inventory_link_id: CHILD_ID }),
    );

    await application.releaseInventory(childCommand({ expectedVersion: 6 }));

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_release_deal_inventory",
        parameters: expect.objectContaining({
          p_expected_version: 6,
          p_inventory_link_id: CHILD_ID,
        }),
      }),
    );
  });

  it("rejects over-broad storage rows at the strict boundary", async () => {
    const { application } = service(
      evidence({ unexpected_private_column: PARTY_ID }),
    );

    await expect(
      application.createDeal(
        command({
          currencyCode: "CAD",
          dealTypeKey: "retail.cash",
          legalEntityId: LEGAL_ENTITY_ID,
          locationId: LOCATION_ID,
          notes: null,
          originatingLeadId: null,
          ownerMembershipId: null,
        }),
      ),
    ).rejects.toBeInstanceOf(M3RpcContractError);
  });
});

describe("T-DEAL-002 trade-in separation contracts", () => {
  const tradeInBody = {
    allowance: { amountMinor: "250000", currencyCode: "CAD" },
    conditionKey: "used.good",
    enteredVehicleFacts: {
      make: "Synthetic",
      model: "Fixture",
      vin: "TESTONLY000000001",
    },
    lenderPartyId: null,
    lienAmount: { amountMinor: "100000", currencyCode: "CAD" },
    odometerUnit: "km" as const,
    odometerValue: 123_456,
    ownerPartyId: PARTY_ID,
    payoffAmount: { amountMinor: "100000", currencyCode: "CAD" },
    taxEligibilityInputs: { ownershipConfirmed: true },
    vehicleId: null,
  };

  it("records trade-in facts and exact amounts without creating inventory", async () => {
    const { application, gateway } = service(
      evidence({ trade_in_id: CHILD_ID, trade_in_version: 1 }),
    );

    await application.createTradeIn(
      entityCommand({ ...tradeInBody, expectedVersion: 4 }),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_create_trade_in",
        parameters: expect.objectContaining({
          p_allowance_minor: "250000",
          p_deal_id: DEAL_ID,
          p_lien_amount_minor: "100000",
          p_payoff_amount_minor: "100000",
        }),
      }),
    );
    expect(
      (gateway.invoke as ReturnType<typeof vi.fn>).mock.calls[0]?.[0]
        .parameters,
    ).not.toHaveProperty("p_inventory_unit_id");
  });

  it("updates trade-in details with deal and child concurrency", async () => {
    const { application, gateway } = service(
      evidence({ trade_in_id: CHILD_ID, trade_in_version: 3 }),
    );

    await application.updateTradeIn(
      entityCommand(
        {
          ...tradeInBody,
          expectedTradeInVersion: 2,
          expectedVersion: 6,
        },
        CHILD_ID,
      ),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_update_trade_in",
        parameters: expect.objectContaining({
          p_expected_trade_in_version: 2,
          p_expected_version: 6,
          p_trade_in_id: CHILD_ID,
        }),
      }),
    );
  });

  it("confirms a separately created inventory unit explicitly", async () => {
    const { application, gateway } = service(
      evidence({ trade_in_id: CHILD_ID, trade_in_version: 4 }),
    );

    await application.confirmTradeInInventory(
      entityCommand(
        {
          expectedTradeInVersion: 3,
          expectedVersion: 7,
          inventoryUnitId: LOCATION_ID,
        },
        CHILD_ID,
      ),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_confirm_trade_in_inventory",
        parameters: expect.objectContaining({
          p_inventory_unit_id: LOCATION_ID,
          p_trade_in_id: CHILD_ID,
        }),
      }),
    );
  });

  it("rejects executable tax-eligibility input before storage", async () => {
    const { application, gateway } = service([]);

    await expect(
      application.createTradeIn(
        entityCommand({
          ...tradeInBody,
          expectedVersion: 1,
          taxEligibilityInputs: { sql: "select current_user" },
        }),
      ),
    ).rejects.toBeInstanceOf(M3ApplicationValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });
});
