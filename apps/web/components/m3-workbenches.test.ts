import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { localizedDealOptionLabel } from "../lib/m3-localized-options";
import { formatM3MinorAmount } from "../lib/m3-money";

describe("T-PAY-001 exact one-time money presentation", () => {
  it("formats integer minor-unit strings without binary-float arithmetic", () => {
    expect(formatM3MinorAmount("1250000", "CAD", "en")).toBe("12,500.00 CAD");
    expect(formatM3MinorAmount("1250000", "CAD", "fr")).toBe("12 500,00 CAD");
    expect(formatM3MinorAmount("-420000", "CAD", "en")).toBe("−4,200.00 CAD");
  });

  it("uses the ISO currency's minor-unit exponent without losing precision", () => {
    expect(formatM3MinorAmount("12500", "JPY", "en")).toBe("12,500 JPY");
    expect(formatM3MinorAmount("12500", "KWD", "en")).toBe("12.500 KWD");
    expect(formatM3MinorAmount("9007199254740991999", "CAD", "en")).toBe(
      "90,071,992,547,409,919.99 CAD",
    );
  });
});

describe("T-DEAL-001 / T-I18N-001 pinned deal options", () => {
  it("uses the selected deal version's localized roles and one-time event types", () => {
    const options = [
      {
        key: "trade_in_owner",
        labels: {
          en: "Trade-in owner",
          fr: "Propriétaire du véhicule d’échange",
        },
      },
    ] as const;
    expect(
      localizedDealOptionLabel(
        options,
        "trade_in_owner",
        "fr",
        "Option indisponible",
      ),
    ).toBe("Propriétaire du véhicule d’échange");
  });

  it("drives detail role and payment selects from the pinned response", () => {
    const source = readFileSync(
      join(process.cwd(), "apps/web/components/m3-deal-workbench.tsx"),
      "utf8",
    );

    expect(source).toContain("deal.participantRoleOptions");
    expect(source).toContain("deal.inventoryRoleOptions");
    expect(source).toContain("deal.oneTimeEventTypeOptions");
    expect(source).not.toContain('defaultValue="sale_vehicle"');
    expect(source).not.toContain('status: "appraised"');
  });

  it("never exposes a missing machine key as visible fallback copy", () => {
    expect(
      localizedDealOptionLabel([], "tenant_specific_key", "en", "Unavailable"),
    ).toBe("Unavailable");
  });
});
