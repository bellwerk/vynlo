import { parseMajorMoneyToMinor } from "./inventory-money";

export function parseMoneyMinorInput(
  value: string,
  currencyCode: string,
): string | null {
  try {
    return parseMajorMoneyToMinor(value, currencyCode);
  } catch {
    throw new TypeError("invalid_money_minor");
  }
}
