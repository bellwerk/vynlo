import { describe, expect, it } from "vitest";

import { m3Messages } from "./m3-messages";

function shape(value: unknown): unknown {
  if (typeof value === "function") return "function";
  if (typeof value !== "object" || value === null) return typeof value;
  return Object.fromEntries(
    Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, entry]) => [key, shape(entry)]),
  );
}

function strings(value: unknown): readonly string[] {
  if (typeof value === "string") return [value];
  if (typeof value !== "object" || value === null) return [];
  return Object.values(value).flatMap(strings);
}

describe("T-I18N-001 / M3-I18N-AC-001 CRM and deal catalogues", () => {
  it("keeps English and French catalogue structure exactly aligned", () => {
    expect(shape(m3Messages.fr)).toEqual(shape(m3Messages.en));
    expect(m3Messages.en.crm.leadCount(1)).toContain("lead");
    expect(m3Messages.fr.crm.leadCount(2)).toContain("prospects");
  });

  it("contains no empty visible copy and labels lender terms truthfully", () => {
    for (const locale of ["en", "fr"] as const) {
      expect(strings(m3Messages[locale]).every((entry) => entry.trim())).toBe(
        true,
      );
    }
    expect(m3Messages.en.deals.financeDisclaimer).toContain("Lender-reported");
    expect(m3Messages.en.deals.financeDisclaimer).toContain("does not");
    expect(m3Messages.fr.deals.financeDisclaimer).toContain("prêteur");
    expect(m3Messages.en.crm.replaceIdentifier).toContain("identifier");
    expect(m3Messages.fr.crm.archiveParty).toContain("Archiver");
  });

  it("localizes every durable participant, inventory-link, and trade-in status", () => {
    for (const locale of ["en", "fr"] as const) {
      expect(
        Object.keys(m3Messages[locale].deals.participantStatusLabels),
      ).toEqual(["active", "released"]);
      expect(
        Object.keys(m3Messages[locale].deals.inventoryLinkStatusLabels),
      ).toEqual(["active", "released"]);
      expect(Object.keys(m3Messages[locale].deals.tradeInStatusLabels)).toEqual(
        ["active", "cancelled", "confirmed"],
      );
      expect(
        Object.keys(m3Messages[locale].deals.inventoryStatusLabels),
      ).toEqual(["active", "archived", "closed", "draft", "pending"]);
    }
  });
});
