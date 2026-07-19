// Stable test IDs: T-COST-002.
import { describe, expect, it } from "vitest";
import { parseMoneyMinorInput } from "./money";

describe("operations workbench money input", () => {
  it("M1-UI-MONEY-001 / T-COST-002 converts currency-aware decimal text to exact minor-unit strings", () => {
    expect(parseMoneyMinorInput("12500.05", "CAD")).toBe("1250005");
    expect(parseMoneyMinorInput("700", "JPY")).toBe("700");
    expect(parseMoneyMinorInput("0.007", "KWD")).toBe("7");
    expect(parseMoneyMinorInput("", "CAD")).toBeNull();
  });

  it("M1-UI-MONEY-002 / T-COST-002 rejects exponent, negative, excessive precision, and bigint overflow", () => {
    for (const value of ["1e3", "-1", "1.234", "92233720368547758.08"]) {
      expect(() => parseMoneyMinorInput(value, "CAD")).toThrow(
        "invalid_money_minor",
      );
    }
  });
});
