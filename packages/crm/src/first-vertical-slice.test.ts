import { describe, expect, it } from "vitest";

import {
  PartyCommandError,
  normalizeCreatePartyCommand,
} from "./first-vertical-slice";

describe("first CRM vertical-slice contracts", () => {
  it("normalizes a minimal person party command", () => {
    expect(
      normalizeCreatePartyCommand({
        idempotencyKey: "party-command-001",
        partyType: "person",
        displayName: "  Synthetic   Customer  ",
      }),
    ).toEqual({
      idempotencyKey: "party-command-001",
      partyType: "person",
      displayName: "Synthetic Customer",
    });
  });

  it("supports an organization without adding tenant-specific fields", () => {
    expect(
      normalizeCreatePartyCommand({
        idempotencyKey: "party-command-002",
        partyType: "organization",
        displayName: "Example Buyer Inc.",
      }).partyType,
    ).toBe("organization");
  });

  it("fails closed for blank names and short idempotency keys", () => {
    expect(() =>
      normalizeCreatePartyCommand({
        idempotencyKey: "short",
        partyType: "person",
        displayName: "Example",
      }),
    ).toThrowError(PartyCommandError);
    expect(() =>
      normalizeCreatePartyCommand({
        idempotencyKey: "party-command-003",
        partyType: "person",
        displayName: "   ",
      }),
    ).toThrowError("invalid_display_name");
  });
});
