import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { POST as reverseCost } from "../inventory-costs/[id]/reversal/route";
import { POST as archiveView } from "../inventory-saved-views/[id]/archive/route";
import {
  GET as listSavedViews,
  POST as saveView,
} from "../inventory-saved-views/route";
import { GET as getCosts, POST as postCost } from "./[id]/costs/route";
import { GET as searchInventory } from "./route";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const inventoryUnitId = "20000000-0000-4000-8000-000000000001";
const costEntryId = "30000000-0000-4000-8000-000000000001";
const categoryId = "40000000-0000-4000-8000-000000000001";
const auditEventId = "50000000-0000-4000-8000-000000000001";
const outboxEventId = "60000000-0000-4000-8000-000000000001";
const correlationId = "70000000-0000-4000-8000-000000000001";
const savedViewId = "80000000-0000-4000-8000-000000000001";
const locationId = "81000000-0000-4000-8000-000000000001";
const publicProjectKey = "sb_publishable_public_project_key_material";
const userToken = "user.header.signature";

function headers(command: boolean): HeadersInit {
  return {
    Authorization: `Bearer ${userToken}`,
    ...(command ? { "Idempotency-Key": "m2-cost-command-0001" } : {}),
    "X-Correlation-Id": correlationId,
    "X-Request-Id": "request-m2-cost-search-0001",
    "X-Workspace-Id": workspaceId,
  };
}

function commandRequest(path: string, body: unknown): Request {
  return new Request(`http://localhost${path}`, {
    body: JSON.stringify(body),
    headers: { ...headers(true), "Content-Type": "application/json" },
    method: "POST",
  });
}

describe("T-COST-001 / T-COST-002 / T-SEARCH-001 Milestone 2 cost/search routes", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", publicProjectKey);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("searches with workspace auth but no command idempotency header", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          advertised_price_minor: "2500000",
          aggregate_version: 2,
          canonical_status: "active",
          currency_code: "CAD",
          days_in_stock: 4,
          estimated_gross_minor: null,
          inventory_unit_id: inventoryUnitId,
          location_id: null,
          location_name: null,
          make: "Example",
          model: "Roadster",
          model_year: 2026,
          posted_cost_minor: null,
          search_rank: 0.5,
          stock_number: "S001",
          updated_at: "2026-07-16T12:00:00.000Z",
          vehicle_trim: null,
          vin: "1HGCM82633A004352",
          workflow_state_key: "ready",
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await searchInventory(
      new Request(
        "http://localhost/api/v1/inventory-units?q=roadster&status=active&page_size=25",
        { headers: headers(false) },
      ),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        items: [
          {
            advertisedPriceMinor: "2500000",
            inventoryUnitId,
            stockNumber: "S001",
          },
        ],
      },
    });
    const [url, init] = fetchImplementation.mock.calls[0] ?? [];
    expect(url).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/search_inventory_units",
    );
    expect(JSON.parse(String(init?.body))).toMatchObject({
      p_page_size: 25,
      p_query: "roadster",
      p_statuses: ["active"],
      p_workspace_id: workspaceId,
    });
  });

  it("posts an exact string money amount and returns the audit receipt", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          aggregate_version: 2,
          audit_event_id: auditEventId,
          cost_entry_id: costEntryId,
          inventory_unit_id: inventoryUnitId,
          outbox_event_id: outboxEventId,
          replayed: false,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await postCost(
      commandRequest(`/api/v1/inventory-units/${inventoryUnitId}/costs`, {
        amountMinor: "9007199254740993",
        categoryDefinitionId: categoryId,
        currencyCode: "CAD",
        description: null,
        expectedVersion: 1,
        incurredOn: "2026-07-16",
        supportingFileId: null,
        vendorPartyId: null,
      }),
      { params: Promise.resolve({ id: inventoryUnitId }) },
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toMatchObject({
      data: { auditEventId, costEntryId, inventoryUnitId },
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({ p_amount_minor: "9007199254740993" });
  });

  it("routes reversals and saved views to separate permission boundaries", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (input) => {
      const url = String(input);
      return url.endsWith("/reverse_inventory_cost_entry")
        ? Response.json([
            {
              aggregate_version: 3,
              audit_event_id: auditEventId,
              inventory_unit_id: inventoryUnitId,
              original_cost_entry_id: costEntryId,
              outbox_event_id: outboxEventId,
              replayed: false,
              reversal_entry_id: "31000000-0000-4000-8000-000000000001",
            },
          ])
        : Response.json([
            {
              audit_event_id: auditEventId,
              replayed: false,
              saved_view_id: savedViewId,
              saved_view_version: 1,
            },
          ]);
    });
    vi.stubGlobal("fetch", fetchImplementation);

    const reversalResponse = await reverseCost(
      commandRequest(`/api/v1/inventory-costs/${costEntryId}/reversal`, {
        expectedVersion: 2,
        reason: "Duplicate",
        reversedOn: "2026-07-16",
      }),
      { params: Promise.resolve({ id: costEntryId }) },
    );
    const viewResponse = await saveView(
      commandRequest("/api/v1/inventory-saved-views", {
        density: "comfortable",
        expectedVersion: null,
        filters: { status: ["active"] },
        layout: "responsive",
        name: "Active inventory",
        savedViewId: null,
        shareScope: "private",
        sort: { direction: "desc", key: "updated_at" },
        visibleColumns: ["stock", "vehicle", "state"],
      }),
    );

    expect(reversalResponse.status).toBe(201);
    expect(viewResponse.status).toBe(201);
    expect(fetchImplementation.mock.calls.map(([url]) => String(url))).toEqual([
      "http://127.0.0.1:54321/rest/v1/rpc/reverse_inventory_cost_entry",
      "http://127.0.0.1:54321/rest/v1/rpc/save_inventory_view",
    ]);
  });

  it("rejects malformed search cursors before PostgREST", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);
    const response = await searchInventory(
      new Request(
        "http://localhost/api/v1/inventory-units?cursor_id=not-a-uuid",
        { headers: headers(false) },
      ),
    );
    expect(response.status).toBe(422);
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it("returns success rather than created for a saved-view update", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>(async () =>
        Response.json([
          {
            audit_event_id: auditEventId,
            replayed: false,
            saved_view_id: savedViewId,
            saved_view_version: 2,
          },
        ]),
      ),
    );

    const response = await saveView(
      commandRequest("/api/v1/inventory-saved-views", {
        density: "comfortable",
        expectedVersion: 1,
        filters: { status: ["active"] },
        layout: "responsive",
        name: "Active inventory",
        savedViewId,
        shareScope: "private",
        sort: { direction: "desc", key: "updated_at" },
        visibleColumns: ["stock", "vehicle", "state"],
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: { created: false, savedViewId, savedViewVersion: 2 },
    });
  });

  it("reads an exact ledger with localized categories and reusable views", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (input) =>
      String(input).endsWith("/get_inventory_unit_costs")
        ? Response.json([
            {
              aggregate_version: 3,
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
              entries: [],
              estimated_gross_minor: "100000",
              has_recent_strong_authentication: true,
              inventory_unit_id: inventoryUnitId,
              last_cost_at: null,
              next_cursor: null,
              posted_cost_minor: "2000000",
              posted_entry_count: 2,
            },
          ])
        : Response.json([
            {
              density: "comfortable",
              filters: { locationIds: [locationId] },
              is_owner: true,
              layout: "responsive",
              name: "Main lot",
              saved_view_id: savedViewId,
              share_scope: "private",
              sort: { direction: "desc", key: "updated_at" },
              status: "active",
              updated_at: "2026-07-16T12:00:00.000Z",
              version: 1,
              visible_columns: ["stock", "vehicle", "location"],
            },
          ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const ledgerResponse = await getCosts(
      new Request(
        `http://localhost/api/v1/inventory-units/${inventoryUnitId}/costs?pageSize=50`,
        { headers: headers(false) },
      ),
      { params: Promise.resolve({ id: inventoryUnitId }) },
    );
    const viewsResponse = await listSavedViews(
      new Request("http://localhost/api/v1/inventory-saved-views", {
        headers: headers(false),
      }),
    );

    await expect(ledgerResponse.json()).resolves.toMatchObject({
      data: {
        categories: [{ labels: { fr: "Reconditionnement" } }],
        postedCostMinor: "2000000",
      },
    });
    await expect(viewsResponse.json()).resolves.toMatchObject({
      data: { items: [{ filters: { locationIds: [locationId] } }] },
    });
  });

  it("archives an owned saved view through a versioned idempotent command", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json([
        {
          audit_event_id: auditEventId,
          replayed: false,
          saved_view_id: savedViewId,
          saved_view_version: 2,
        },
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);
    const response = await archiveView(
      commandRequest(`/api/v1/inventory-saved-views/${savedViewId}/archive`, {
        expectedVersion: 1,
      }),
      { params: Promise.resolve({ id: savedViewId }) },
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: { savedViewId, savedViewVersion: 2 },
    });
  });
});
