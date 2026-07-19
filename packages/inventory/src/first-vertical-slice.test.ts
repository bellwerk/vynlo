import { describe, expect, it } from "vitest";

import {
  InventoryCommandError,
  formatStockNumber,
  normalizeCreateInventoryUnitCommand,
  normalizeVinInput,
} from "./first-vertical-slice";

const validCommand = {
  idempotencyKey: "inventory-command-001",
  stockNumberDefinitionId: "71000000-0000-4000-8000-000000000001",
  vin: " 1hgcm82633a004352 ",
  modelYear: 2024,
  make: " Example ",
  model: " Roadster ",
  acquisitionDate: "2026-07-16",
  odometer: { value: 12_345, unit: "km" as const },
  currencyCode: "cad",
  advertisedPriceMinor: 2_500_000,
  publicNotes: " Synthetic fixture ",
} as const;

describe("first inventory vertical-slice contracts", () => {
  it("T-INV-002 normalizes a typed or pasted VIN without a camera dependency", () => {
    expect(normalizeVinInput(" 1hgcm82633a004352 ")).toBe("1HGCM82633A004352");
  });

  it.each(["1HGCM82633A00435", "1HGCM82633I004352", "", "é".repeat(17)])(
    "T-INV-002 rejects invalid VIN input %s",
    (vin) => {
      expect(() => normalizeVinInput(vin)).toThrowError(InventoryCommandError);
    },
  );

  it("normalizes the phone-usable create command and preserves integer minor units", () => {
    expect(normalizeCreateInventoryUnitCommand(validCommand)).toEqual({
      ...validCommand,
      idempotencyKey: "inventory-command-001",
      vin: "1HGCM82633A004352",
      make: "Example",
      model: "Roadster",
      currencyCode: "CAD",
      publicNotes: "Synthetic fixture",
    });
  });

  it("rejects binary-float or negative monetary inputs", () => {
    expect(() =>
      normalizeCreateInventoryUnitCommand({
        ...validCommand,
        advertisedPriceMinor: 1.5,
      }),
    ).toThrowError("invalid_money_minor");
    expect(() =>
      normalizeCreateInventoryUnitCommand({
        ...validCommand,
        advertisedPriceMinor: -1,
      }),
    ).toThrowError("invalid_money_minor");
  });

  it("T-NUM-001 formats deterministic padded stock numbers without reuse logic", () => {
    expect(formatStockNumber("S", 5, 42)).toBe("S00042");
    expect(formatStockNumber("", 2, 123)).toBe("123");
  });
});
