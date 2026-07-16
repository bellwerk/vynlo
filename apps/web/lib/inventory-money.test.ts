import { describe, expect, it } from "vitest";
import {
  formatMinorMoney,
  minorMoneyToMajorInput,
  parseMajorMoneyToMinor,
} from "./inventory-money";

describe("T-COST-002 inventory money helpers", () => {
  it("converts user-entered major units without binary floating point", () => {
    expect(parseMajorMoneyToMinor(" ", "CAD")).toBeNull();
    expect(parseMajorMoneyToMinor("54995.09", "CAD")).toBe("5499509");
    expect(parseMajorMoneyToMinor("0.5", "CAD")).toBe("50");
    expect(parseMajorMoneyToMinor("100", "JPY")).toBe("100");
    expect(parseMajorMoneyToMinor("1.234", "KWD")).toBe("1234");
  });

  it("preserves bigint precision while formatting minor units", () => {
    expect(formatMinorMoney("900719925474099199", "CAD", "en-CA")).toContain(
      "9,007,199,254,740,991.99",
    );
    expect(formatMinorMoney("-50", "CAD", "en-CA")).toContain("-$0.50");
    expect(formatMinorMoney("1234", "KWD", "en-CA")).toContain("1.234");
    expect(minorMoneyToMajorInput("100", "JPY")).toBe("100");
    expect(minorMoneyToMajorInput("1234", "KWD")).toBe("1.234");
  });

  it("rejects malformed and out-of-range values", () => {
    expect(() => parseMajorMoneyToMinor("-1", "CAD")).toThrow(
      "invalid_money_range",
    );
    expect(() => parseMajorMoneyToMinor("54,995", "CAD")).toThrow(
      "invalid_money_range",
    );
    expect(() => parseMajorMoneyToMinor("92233720368547758.08", "CAD")).toThrow(
      "invalid_money_range",
    );
    expect(() => parseMajorMoneyToMinor("1.00", "JPY")).toThrow(
      "invalid_money_range",
    );
  });
});
