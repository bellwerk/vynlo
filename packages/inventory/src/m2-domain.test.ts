import { describe, expect, it } from "vitest";

import {
  INVENTORY_READ_INTERNAL_PERMISSION,
  INVENTORY_UPDATE_INTERNAL_PERMISSION,
  INVENTORY_UPDATE_PERMISSION,
  InventoryDomainError,
  calculateDaysInStock,
  calculateEstimatedInventoryGross,
  normalizeTypedOrPastedVin,
  parseInventoryPrice,
  planInventoryInternalNotesUpdate,
  planInventoryUnitUpdate,
  planOpenInventoryHolding,
  readInventoryInternalNotes,
  withoutInventoryInternalNotes,
  type InventoryUnitMutableSnapshot,
} from "./m2-domain";

const WORKSPACE_ID = "00000000-0000-4000-8000-000000000001";
const OTHER_WORKSPACE_ID = "00000000-0000-4000-8000-000000000002";
const VEHICLE_ID = "10000000-0000-4000-8000-000000000001";
const INVENTORY_ID = "20000000-0000-4000-8000-000000000001";
const PRIOR_INVENTORY_ID = "20000000-0000-4000-8000-000000000002";
const LOCATION_A_ID = "30000000-0000-4000-8000-000000000001";
const LOCATION_B_ID = "30000000-0000-4000-8000-000000000002";

function expectDomainError(
  operation: () => unknown,
  code: InstanceType<typeof InventoryDomainError>["code"],
): void {
  expect(operation).toThrowError(InventoryDomainError);
  try {
    operation();
  } catch (error) {
    expect(error).toMatchObject({ code });
  }
}

const currentInventory: InventoryUnitMutableSnapshot = {
  id: INVENTORY_ID,
  vehicleId: VEHICLE_ID,
  version: 7,
  currencyCode: "CAD",
  conditionKey: null,
  locationId: LOCATION_A_ID,
  advertisedPrice: parseInventoryPrice({
    minorUnits: "2500000",
    currencyCode: "CAD",
  }),
  expectedSalePrice: parseInventoryPrice({
    minorUnits: "2400000",
    currencyCode: "CAD",
  }),
  publicNotes: null,
  internalNotes: "Acquired at synthetic auction fixture.",
};

describe("T-INV-001 / T-INV-002 / T-INV-004 / T-COST-002 M2 inventory domain contracts", () => {
  it("M2-INV-AC-001 / T-INV-002 normalizes typed or pasted VIN input", () => {
    expect(normalizeTypedOrPastedVin("\t1hgcm82633a004352\r\n")).toBe(
      "1HGCM82633A004352",
    );

    for (const value of [
      "1HGCM82633A00435",
      "1HGCM82633I004352",
      "1HGCM82633O004352",
      "1HGCM82633Q004352",
      17,
    ]) {
      expectDomainError(() => normalizeTypedOrPastedVin(value), "invalid_vin");
    }
  });

  it("M2-INV-AC-005 / T-INV-001 keeps a vehicle separate from each holding episode", () => {
    const plan = planOpenInventoryHolding({
      authoritativeWorkspaceId: WORKSPACE_ID,
      inventoryUnitId: INVENTORY_ID,
      acquiredOn: "2026-07-16",
      vehicle: {
        id: VEHICLE_ID,
        workspaceId: WORKSPACE_ID,
        vin: "1HGCM82633A004352",
        factsVersion: 2,
      },
      existingEpisodes: [
        {
          id: PRIOR_INVENTORY_ID,
          workspaceId: WORKSPACE_ID,
          vehicleId: VEHICLE_ID,
          canonicalStatus: "closed",
          acquiredOn: "2024-01-04",
          closedOn: "2025-09-30",
        },
      ],
    });

    expect(plan).toEqual({
      inventoryUnitId: INVENTORY_ID,
      vehicleId: VEHICLE_ID,
      acquiredOn: "2026-07-16",
      initialCanonicalStatus: "draft",
      reacquisition: true,
      previousHoldingEpisodeIds: [PRIOR_INVENTORY_ID],
    });
    expect(plan.inventoryUnitId).not.toBe(plan.vehicleId);
    expect(Object.isFrozen(plan)).toBe(true);
  });

  it("M2-INV-AC-005 blocks a second open episode and foreign workspace history", () => {
    const input = {
      authoritativeWorkspaceId: WORKSPACE_ID,
      inventoryUnitId: INVENTORY_ID,
      acquiredOn: "2026-07-16",
      vehicle: {
        id: VEHICLE_ID,
        workspaceId: WORKSPACE_ID,
        vin: "1HGCM82633A004352",
        factsVersion: 1,
      },
    } as const;

    expectDomainError(
      () =>
        planOpenInventoryHolding({
          ...input,
          existingEpisodes: [
            {
              id: PRIOR_INVENTORY_ID,
              workspaceId: WORKSPACE_ID,
              vehicleId: VEHICLE_ID,
              canonicalStatus: "active",
              acquiredOn: "2026-01-01",
              closedOn: null,
            },
          ],
        }),
      "open_holding_episode_exists",
    );

    expectDomainError(
      () =>
        planOpenInventoryHolding({
          ...input,
          existingEpisodes: [
            {
              id: PRIOR_INVENTORY_ID,
              workspaceId: OTHER_WORKSPACE_ID,
              vehicleId: VEHICLE_ID,
              canonicalStatus: "closed",
              acquiredOn: "2024-01-01",
              closedOn: "2025-01-01",
            },
          ],
        }),
      "invalid_holding_episode",
    );

    expectDomainError(
      () =>
        planOpenInventoryHolding({
          ...input,
          inventoryUnitId: VEHICLE_ID,
          existingEpisodes: [],
        }),
      "vehicle_holding_identity_conflict",
    );
  });

  it("M2-INV-AC-007 parses exact integer minor-unit prices and ISO currency", () => {
    const price = parseInventoryPrice({
      minorUnits: "9007199254740993",
      currencyCode: " cad ",
    });

    expect(price).toEqual({
      minorUnits: 9_007_199_254_740_993n,
      currencyCode: "CAD",
    });
    expect(Object.isFrozen(price)).toBe(true);

    for (const minorUnits of [
      1.25,
      "1.25",
      "1e3",
      "9".repeat(1_000),
      -1n,
      Number.MAX_VALUE,
    ]) {
      expectDomainError(
        () => parseInventoryPrice({ minorUnits, currencyCode: "CAD" }),
        "invalid_money_minor",
      );
    }
    expectDomainError(
      () =>
        parseInventoryPrice({
          minorUnits: "9223372036854775808",
          currencyCode: "CAD",
        }),
      "invalid_money_minor",
    );
    expectDomainError(
      () => parseInventoryPrice({ minorUnits: 100, currencyCode: "CA" }),
      "invalid_currency",
    );
  });

  it("M2-INV-AC-005 / T-INV-004 plans condition, location, price and note changes at one expected version", () => {
    const plan = planInventoryUnitUpdate({
      current: currentInventory,
      effectivePermissionKeys: [INVENTORY_UPDATE_PERMISSION],
      command: {
        expectedVersion: 7,
        conditionKey: "used.clean",
        locationId: LOCATION_B_ID,
        locationChangeReason: "Moved to the retail display area.",
        advertisedPrice: {
          minorUnits: "2600000",
          currencyCode: "cad",
        },
        publicNotes: "  Synthetic public note.  ",
      },
    });

    expect(plan).toMatchObject({
      previousVersion: 7,
      nextVersion: 8,
      changedFields: [
        "condition",
        "location",
        "advertised_price",
        "public_notes",
      ],
      locationTransfer: {
        fromLocationId: LOCATION_A_ID,
        toLocationId: LOCATION_B_ID,
        reason: "Moved to the retail display area.",
      },
      next: {
        version: 8,
        conditionKey: "used.clean",
        locationId: LOCATION_B_ID,
        advertisedPrice: { minorUnits: 2_600_000n, currencyCode: "CAD" },
        publicNotes: "Synthetic public note.",
      },
    });
    expect(plan.next.internalNotes).toBe(currentInventory.internalNotes);
  });

  it("M2-INV-AC-005 rejects stale, unauthorized, unreasoned and cross-currency updates", () => {
    expectDomainError(
      () =>
        planInventoryUnitUpdate({
          current: currentInventory,
          effectivePermissionKeys: [INVENTORY_UPDATE_PERMISSION],
          command: { expectedVersion: 6, conditionKey: "used.clean" },
        }),
      "inventory_version_conflict",
    );
    expectDomainError(
      () =>
        planInventoryUnitUpdate({
          current: currentInventory,
          effectivePermissionKeys: [],
          command: { expectedVersion: 7, conditionKey: "used.clean" },
        }),
      "permission_required",
    );
    expectDomainError(
      () =>
        planInventoryUnitUpdate({
          current: currentInventory,
          effectivePermissionKeys: [INVENTORY_UPDATE_PERMISSION],
          command: {
            expectedVersion: 7,
            locationId: LOCATION_B_ID,
          },
        }),
      "location_reason_required",
    );
    expectDomainError(
      () =>
        planInventoryUnitUpdate({
          current: currentInventory,
          effectivePermissionKeys: [INVENTORY_UPDATE_PERMISSION],
          command: {
            expectedVersion: 7,
            advertisedPrice: { minorUnits: 100, currencyCode: "USD" },
          },
        }),
      "money_currency_mismatch",
    );
  });

  it("M2-INV-AC-005 keeps internal notes out of ordinary updates and projections", () => {
    expectDomainError(
      () =>
        planInventoryUnitUpdate({
          current: currentInventory,
          effectivePermissionKeys: [INVENTORY_UPDATE_PERMISSION],
          command: {
            expectedVersion: 7,
            internalNotes: "Injected through an untyped request.",
          } as never,
        }),
      "internal_notes_boundary",
    );

    const external = withoutInventoryInternalNotes(currentInventory);
    expect(external).not.toHaveProperty("internalNotes");
    expectDomainError(
      () => readInventoryInternalNotes(currentInventory, []),
      "permission_required",
    );
    expect(
      readInventoryInternalNotes(currentInventory, [
        INVENTORY_READ_INTERNAL_PERMISSION,
      ]),
    ).toBe(currentInventory.internalNotes);

    const updated = planInventoryInternalNotesUpdate({
      current: currentInventory,
      command: { expectedVersion: 7, internalNotes: "  Reviewed.  " },
      effectivePermissionKeys: [INVENTORY_UPDATE_INTERNAL_PERMISSION],
    });
    expect(updated).toMatchObject({ version: 8, internalNotes: "Reviewed." });
  });

  it("M2-INV-AC-006 computes calendar days in stock and stops on closure", () => {
    expect(
      calculateDaysInStock({
        acquiredOn: "2026-07-01",
        asOf: "2026-07-16",
      }),
    ).toBe(15);
    expect(
      calculateDaysInStock({
        acquiredOn: "2026-07-01",
        closedOn: "2026-07-10",
        asOf: "2026-07-16",
      }),
    ).toBe(9);
    expect(
      calculateDaysInStock({
        acquiredOn: "2026-07-16",
        asOf: "2026-07-16",
      }),
    ).toBe(0);
    expectDomainError(
      () =>
        calculateDaysInStock({
          acquiredOn: "2026-07-16",
          asOf: "2026-07-15",
        }),
      "invalid_days_in_stock_range",
    );
  });

  it("M2-INV-AC-007 derives estimated gross from expected price and the posted cost ledger", () => {
    const gross = calculateEstimatedInventoryGross({
      expectedSalePrice: parseInventoryPrice({
        minorUnits: "9007199254740993",
        currencyCode: "CAD",
      }),
      advertisedPrice: parseInventoryPrice({
        minorUnits: "8000000000000000",
        currencyCode: "CAD",
      }),
      costEntries: [
        {
          entryId: "acquisition",
          status: "posted",
          kind: "cost",
          amount: parseInventoryPrice({
            minorUnits: "8000000000000000",
            currencyCode: "CAD",
          }),
        },
        {
          entryId: "repair-draft",
          status: "draft",
          kind: "cost",
          amount: parseInventoryPrice({
            minorUnits: "999999",
            currencyCode: "CAD",
          }),
        },
        {
          entryId: "partial-reversal",
          status: "posted",
          kind: "reversal",
          amount: parseInventoryPrice({
            minorUnits: "100000000000000",
            currencyCode: "CAD",
          }),
        },
      ],
    });

    expect(gross).toEqual({
      basis: "expected_sale_price",
      currencyCode: "CAD",
      basisPriceMinor: 9_007_199_254_740_993n,
      postedCostMinor: 8_000_000_000_000_000n,
      postedReversalMinor: 100_000_000_000_000n,
      netCostMinor: 7_900_000_000_000_000n,
      estimatedGrossMinor: 1_107_199_254_740_993n,
    });
    expect(
      calculateEstimatedInventoryGross({
        expectedSalePrice: null,
        advertisedPrice: null,
        costEntries: [],
      }),
    ).toBeNull();
    expectDomainError(
      () =>
        calculateEstimatedInventoryGross({
          expectedSalePrice: parseInventoryPrice({
            minorUnits: 100,
            currencyCode: "CAD",
          }),
          advertisedPrice: null,
          costEntries: [
            {
              entryId: "foreign-cost",
              status: "posted",
              kind: "cost",
              amount: parseInventoryPrice({
                minorUnits: 10,
                currencyCode: "USD",
              }),
            },
          ],
        }),
      "money_currency_mismatch",
    );
    expectDomainError(
      () =>
        calculateEstimatedInventoryGross({
          expectedSalePrice: parseInventoryPrice({
            minorUnits: 100,
            currencyCode: "CAD",
          }),
          advertisedPrice: parseInventoryPrice({
            minorUnits: 100,
            currencyCode: "USD",
          }),
          costEntries: [],
        }),
      "money_currency_mismatch",
    );
    expectDomainError(
      () =>
        calculateEstimatedInventoryGross({
          expectedSalePrice: null,
          advertisedPrice: parseInventoryPrice({
            minorUnits: 100,
            currencyCode: "CAD",
          }),
          costEntries: [
            {
              entryId: "invalid-over-reversal",
              status: "posted",
              kind: "reversal",
              amount: parseInventoryPrice({
                minorUnits: 101,
                currencyCode: "CAD",
              }),
            },
          ],
        }),
      "invalid_cost_entry",
    );

    expect(
      calculateEstimatedInventoryGross({
        expectedSalePrice: null,
        advertisedPrice: parseInventoryPrice({
          minorUnits: 500,
          currencyCode: "CAD",
        }),
        costEntries: [
          {
            entryId: "posted-cost",
            status: "posted",
            kind: "cost",
            amount: parseInventoryPrice({
              minorUnits: 125,
              currencyCode: "CAD",
            }),
          },
        ],
      }),
    ).toMatchObject({
      basis: "advertised_price",
      basisPriceMinor: 500n,
      estimatedGrossMinor: 375n,
    });
  });
});
