import { describe, expect, it, vi } from "vitest";

import type { AuthenticatedRpcGateway } from "./vertical-slice-api";
import {
  M2CostSearchApplicationService,
  M2CostSearchRpcContractError,
  M2CostSearchValidationError,
} from "./m2-cost-search-api";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const inventoryUnitId = "20000000-0000-4000-8000-000000000001";
const costEntryId = "30000000-0000-4000-8000-000000000001";
const categoryId = "40000000-0000-4000-8000-000000000001";
const auditEventId = "50000000-0000-4000-8000-000000000001";
const outboxEventId = "60000000-0000-4000-8000-000000000001";
const locationId = "70000000-0000-4000-8000-000000000001";
const savedViewId = "80000000-0000-4000-8000-000000000001";

function fixture(result: unknown) {
  const gateway: AuthenticatedRpcGateway = {
    invoke: vi.fn(async () => result),
  };
  return { gateway, service: new M2CostSearchApplicationService(gateway) };
}

function command(body: unknown, entityId = inventoryUnitId) {
  return {
    body,
    entityId,
    metadata: {
      accessToken: "user.header.signature",
      correlationId: "90000000-0000-4000-8000-000000000001",
      idempotencyKey: "cost-command-0001",
      requestId: "request-m2-cost-1",
      workspaceId,
    },
  };
}

describe("T-COST-001 / T-COST-002 / T-SEARCH-001 M2CostSearchApplicationService", () => {
  it("posts exact integer-minor-unit cost data through the workspace RPC", async () => {
    const { gateway, service } = fixture([
      {
        aggregate_version: 3,
        audit_event_id: auditEventId,
        cost_entry_id: costEntryId,
        inventory_unit_id: inventoryUnitId,
        outbox_event_id: outboxEventId,
        replayed: false,
      },
    ]);

    await expect(
      service.postCost(
        command({
          amountMinor: "9007199254740993",
          categoryDefinitionId: categoryId,
          currencyCode: "cad",
          description: "Transport",
          expectedVersion: 2,
          incurredOn: "2026-07-15",
          supportingFileId: null,
          vendorPartyId: null,
        }),
      ),
    ).resolves.toEqual({
      aggregateVersion: 3,
      auditEventId,
      costEntryId,
      inventoryUnitId,
      outboxEventId,
      replayed: false,
    });
    expect(gateway.invoke).toHaveBeenCalledWith({
      accessToken: "user.header.signature",
      functionName: "post_inventory_cost_entry",
      parameters: expect.objectContaining({
        p_amount_minor: "9007199254740993",
        p_category_definition_id: categoryId,
        p_currency_code: "CAD",
        p_inventory_unit_id: inventoryUnitId,
        p_workspace_id: workspaceId,
      }),
    });
  });

  it("reverses instead of mutating a posted entry", async () => {
    const reversalEntryId = "31000000-0000-4000-8000-000000000001";
    const { gateway, service } = fixture([
      {
        aggregate_version: 4,
        audit_event_id: auditEventId,
        inventory_unit_id: inventoryUnitId,
        original_cost_entry_id: costEntryId,
        outbox_event_id: outboxEventId,
        replayed: false,
        reversal_entry_id: reversalEntryId,
      },
    ]);

    await expect(
      service.reverseCost(
        command(
          {
            expectedVersion: 3,
            reason: "Duplicate invoice",
            reversedOn: "2026-07-16",
          },
          costEntryId,
        ),
      ),
    ).resolves.toMatchObject({
      originalCostEntryId: costEntryId,
      reversalEntryId,
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "reverse_inventory_cost_entry",
        parameters: expect.objectContaining({
          p_cost_entry_id: costEntryId,
          p_reason: "Duplicate invoice",
        }),
      }),
    );
  });

  it("saves only an allowlisted, versioned view definition", async () => {
    const { gateway, service } = fixture([
      {
        audit_event_id: auditEventId,
        replayed: false,
        saved_view_id: savedViewId,
        saved_view_version: 1,
      },
    ]);

    await expect(
      service.saveView({
        body: {
          density: "comfortable",
          expectedVersion: null,
          filters: { locationIds: [locationId], status: ["active"] },
          layout: "responsive",
          name: "Ready inventory",
          savedViewId: null,
          shareScope: "private",
          sort: { direction: "desc", key: "updated_at" },
          visibleColumns: ["stock", "vehicle", "state", "price"],
        },
        metadata: command({}).metadata,
      }),
    ).resolves.toMatchObject({
      created: true,
      savedViewId,
      savedViewVersion: 1,
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "save_inventory_view",
        parameters: expect.objectContaining({
          p_filters: { locationIds: [locationId], status: ["active"] },
          p_saved_view_id: null,
        }),
      }),
    );
  });

  it("fails closed when a saved-view update echoes another entity", async () => {
    const { service } = fixture([
      {
        audit_event_id: auditEventId,
        replayed: false,
        saved_view_id: "80000000-0000-4000-8000-000000000099",
        saved_view_version: 2,
      },
    ]);

    await expect(
      service.saveView({
        body: {
          density: "comfortable",
          expectedVersion: 1,
          filters: { status: ["active"] },
          layout: "responsive",
          name: "Ready inventory",
          savedViewId,
          shareScope: "private",
          sort: { direction: "desc", key: "updated_at" },
          visibleColumns: ["stock", "vehicle", "state", "price"],
        },
        metadata: command({}).metadata,
      }),
    ).rejects.toBeInstanceOf(M2CostSearchRpcContractError);
  });

  it("returns permission-shaped search rows without losing bigint money", async () => {
    const { gateway, service } = fixture([
      {
        advertised_price_minor: "9223372036854775807",
        aggregate_version: 7,
        canonical_status: "active",
        currency_code: "CAD",
        days_in_stock: 12,
        estimated_gross_minor: "-100",
        inventory_unit_id: inventoryUnitId,
        location_id: locationId,
        location_name: "Synthetic North",
        make: "Example",
        model: "Roadster",
        model_year: 2025,
        posted_cost_minor: "500",
        search_rank: 0.75,
        stock_number: "S001",
        updated_at: "2026-07-16T12:00:00.000Z",
        vehicle_trim: "Touring",
        vin: "1HGCM82633A004352",
        workflow_state_key: "ready",
      },
    ]);

    await expect(
      service.search({
        accessToken: "user.header.signature",
        query: {
          locationIds: [locationId],
          pageSize: 1,
          query: "roadster",
          statuses: ["active"],
        },
        workspaceId,
      }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          advertisedPriceMinor: "9223372036854775807",
          estimatedGrossMinor: "-100",
          postedCostMinor: "500",
        }),
      ],
      nextCursor: {
        id: inventoryUnitId,
        rank: 0.75,
        updatedAt: "2026-07-16T12:00:00.000Z",
      },
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "search_inventory_units",
        parameters: expect.objectContaining({
          p_location_ids: [locationId],
          p_page_size: 1,
          p_query: "roadster",
          p_statuses: ["active"],
        }),
      }),
    );
  });

  it("rejects unsafe input before RPC invocation", async () => {
    const { gateway, service } = fixture([]);
    await expect(
      service.postCost(
        command({
          amountMinor: "1.25",
          categoryDefinitionId: categoryId,
          currencyCode: "CAD",
          description: null,
          expectedVersion: 1,
          incurredOn: "2026-07-16",
          supportingFileId: null,
          vendorPartyId: null,
          workspaceId,
        }),
      ),
    ).rejects.toBeInstanceOf(M2CostSearchValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });

  it("fails closed on an unexpected financial projection", async () => {
    const { service } = fixture([
      {
        advertised_price_minor: 9_007_199_254_740_993,
        aggregate_version: 1,
        canonical_status: "active",
        currency_code: "CAD",
        days_in_stock: 1,
        estimated_gross_minor: null,
        inventory_unit_id: inventoryUnitId,
        location_id: null,
        location_name: null,
        make: null,
        model: null,
        model_year: null,
        posted_cost_minor: null,
        search_rank: 0,
        stock_number: "S001",
        updated_at: "2026-07-16T12:00:00.000Z",
        vehicle_trim: null,
        vin: "1HGCM82633A004352",
        workflow_state_key: "active",
      },
    ]);
    await expect(
      service.search({ accessToken: "token", query: {}, workspaceId }),
    ).rejects.toBeInstanceOf(M2CostSearchRpcContractError);
  });
});

describe("T-COST-001 / T-COST-002 / T-SEARCH-001 M2 cost ledger and reusable saved-view reads", () => {
  it("returns exact minor-unit ledger values and localized active categories", async () => {
    const { gateway, service } = fixture([
      {
        aggregate_version: 9,
        can_create: true,
        can_reverse: true,
        categories: [
          {
            id: categoryId,
            key: "reconditioning",
            labels: { en: "Reconditioning", fr: "Reconditionnement" },
            version: 1,
          },
        ],
        currency_code: "CAD",
        entries: [
          {
            aggregateVersion: 9,
            amountMinor: "9007199254740993",
            categoryDefinitionId: categoryId,
            categoryKey: "reconditioning",
            categoryLabels: {
              en: "Reconditioning",
              fr: "Reconditionnement",
            },
            createdAt: "2026-07-16T12:00:00.000Z",
            currencyCode: "CAD",
            description: "Synthetic fixture",
            effectiveStatus: "posted",
            entryKind: "cost",
            id: costEntryId,
            incurredOn: "2026-07-16",
            reversalOfId: null,
            supportingFileId: null,
            vendorPartyId: null,
          },
        ],
        estimated_gross_minor: "-100",
        has_recent_strong_authentication: true,
        inventory_unit_id: inventoryUnitId,
        last_cost_at: "2026-07-16T12:00:00.000Z",
        next_cursor: {
          createdAt: "2026-07-16T12:00:00.000Z",
          id: costEntryId,
        },
        posted_cost_minor: "9007199254740993",
        posted_entry_count: 1,
      },
    ]);
    await expect(
      service.getCosts({
        accessToken: "user.header.signature",
        entityId: inventoryUnitId,
        query: { pageSize: 25 },
        workspaceId,
      }),
    ).resolves.toMatchObject({
      categories: [{ id: categoryId, labels: { fr: "Reconditionnement" } }],
      entries: [{ amountMinor: "9007199254740993" }],
      estimatedGrossMinor: "-100",
      postedCostMinor: "9007199254740993",
    });
    expect(gateway.invoke).toHaveBeenCalledWith({
      accessToken: "user.header.signature",
      functionName: "get_inventory_unit_costs",
      parameters: {
        p_before_created_at: null,
        p_before_id: null,
        p_inventory_unit_id: inventoryUnitId,
        p_page_size: 25,
        p_workspace_id: workspaceId,
      },
    });
  });

  it("lists full owner/shared saved-view configurations for reuse", async () => {
    const { service } = fixture([
      {
        density: "compact",
        filters: { locationIds: [locationId], status: ["active"] },
        is_owner: true,
        layout: "responsive",
        name: "Main lot",
        saved_view_id: savedViewId,
        share_scope: "private",
        sort: { direction: "desc", key: "updated_at" },
        status: "active",
        updated_at: "2026-07-16T12:00:00.000Z",
        version: 3,
        visible_columns: ["stock", "vehicle", "location"],
      },
    ]);
    await expect(
      service.listSavedViews({
        accessToken: "user.header.signature",
        workspaceId,
      }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          filters: { locationIds: [locationId], status: ["active"] },
          isOwner: true,
          savedViewId,
          version: 3,
        }),
      ],
    });
  });

  it("archives an owner view with optimistic version and idempotency metadata", async () => {
    const { gateway, service } = fixture([
      {
        audit_event_id: auditEventId,
        replayed: false,
        saved_view_id: savedViewId,
        saved_view_version: 4,
      },
    ]);
    await expect(
      service.archiveView(command({ expectedVersion: 3 }, savedViewId)),
    ).resolves.toEqual({
      auditEventId,
      replayed: false,
      savedViewId,
      savedViewVersion: 4,
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "archive_inventory_saved_view",
        parameters: expect.objectContaining({
          p_expected_version: 3,
          p_saved_view_id: savedViewId,
        }),
      }),
    );
  });

  it("rejects a partial cost cursor before database access", async () => {
    const { gateway, service } = fixture([]);
    await expect(
      service.getCosts({
        accessToken: "user.header.signature",
        entityId: inventoryUnitId,
        query: { cursor: { createdAt: "2026-07-16T12:00:00.000Z" } },
        workspaceId,
      }),
    ).rejects.toBeInstanceOf(M2CostSearchValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });
});
