export function parseMoneyMinorInput(value: string): number | null {
  const normalized = value.trim();
  if (!normalized) {
    return null;
  }
  if (!/^\d+(?:\.\d{1,2})?$/u.test(normalized)) {
    throw new TypeError("invalid_money_minor");
  }
  const [major = "0", fraction = ""] = normalized.split(".");
  const minor = BigInt(major) * 100n + BigInt(fraction.padEnd(2, "0"));
  if (minor > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new TypeError("invalid_money_minor");
  }
  return Number(minor);
}
