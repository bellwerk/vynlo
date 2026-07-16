import { describe, expect, it } from "vitest";
import { parseMoneyMinorInput } from "./money";

describe("operations workbench money input", () => {
  it("M1-UI-MONEY-001 converts decimal text to exact minor units", () => {
    expect(parseMoneyMinorInput("12500.05")).toBe(1_250_005);
    expect(parseMoneyMinorInput("0.7")).toBe(70);
    expect(parseMoneyMinorInput("")).toBeNull();
  });

  it("M1-UI-MONEY-002 rejects exponent, negative, and unsafe values", () => {
    for (const value of ["1e3", "-1", "1.234", "90071992547410.00"]) {
      expect(() => parseMoneyMinorInput(value)).toThrow("invalid_money_minor");
    }
  });
});
