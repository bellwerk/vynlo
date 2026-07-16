import { describe, expect, it } from "vitest";

import {
  DealDraftCommandError,
  normalizeCreateDealDraftCommand,
} from "./first-vertical-slice";

const validCommand = {
  idempotencyKey: "deal-command-001",
  dealTypeKey: " Retail.Cash ",
  currencyCode: "cad",
  participant: {
    partyId: "81000000-0000-4000-8000-000000000001",
    roleKey: " Buyer ",
  },
  inventory: {
    inventoryUnitId: "73000000-0000-4000-8000-000000000001",
    roleKey: " Sold ",
  },
  notes: " Synthetic draft ",
} as const;

describe("first deal vertical-slice contracts", () => {
  it("normalizes a phone-usable draft with explicit party and inventory links", () => {
    expect(normalizeCreateDealDraftCommand(validCommand)).toEqual({
      ...validCommand,
      dealTypeKey: "retail.cash",
      currencyCode: "CAD",
      participant: {
        partyId: validCommand.participant.partyId,
        roleKey: "buyer",
      },
      inventory: {
        inventoryUnitId: validCommand.inventory.inventoryUnitId,
        roleKey: "sold",
      },
      notes: "Synthetic draft",
    });
  });

  it("keeps owner and workspace authority out of the request-body contract", () => {
    const normalized = normalizeCreateDealDraftCommand(validCommand);
    expect(normalized).not.toHaveProperty("workspaceId");
    expect(normalized).not.toHaveProperty("ownerMembershipId");
  });

  it("rejects malformed entity IDs and tenant-code-like role text", () => {
    expect(() =>
      normalizeCreateDealDraftCommand({
        ...validCommand,
        participant: { ...validCommand.participant, partyId: "party-1" },
      }),
    ).toThrowError(DealDraftCommandError);
    expect(() =>
      normalizeCreateDealDraftCommand({
        ...validCommand,
        inventory: { ...validCommand.inventory, roleKey: "Sold Vehicle!" },
      }),
    ).toThrowError("invalid_inventory_role_key");
  });
});
