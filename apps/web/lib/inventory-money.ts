const POSTGRES_BIGINT_MAX = 9_223_372_036_854_775_807n;

function currencyFractionDigits(currencyCode: string): number {
  const normalizedCurrency = currencyCode.trim().toUpperCase();
  if (!/^[A-Z]{3}$/u.test(normalizedCurrency)) {
    throw new TypeError("invalid_currency_code");
  }
  try {
    const fractionDigits = new Intl.NumberFormat("en", {
      currency: normalizedCurrency,
      style: "currency",
    }).resolvedOptions().maximumFractionDigits;
    if (fractionDigits === undefined || !Number.isInteger(fractionDigits)) {
      throw new TypeError("invalid_currency_code");
    }
    return fractionDigits;
  } catch {
    throw new TypeError("invalid_currency_code");
  }
}

export function parseMajorMoneyToMinor(
  value: string,
  currencyCode: string,
): string | null {
  const normalized = value.trim();
  if (normalized === "") {
    return null;
  }
  const fractionDigits = currencyFractionDigits(currencyCode);
  const pattern = new RegExp(
    fractionDigits === 0
      ? "^(?:0|[1-9]\\d{0,18})$"
      : `^(?:0|[1-9]\\d{0,18})(?:\\.\\d{1,${fractionDigits}})?$`,
    "u",
  );
  if (!pattern.test(normalized)) {
    throw new TypeError("invalid_money_range");
  }
  const [major = "0", fraction = ""] = normalized.split(".");
  const divisor = 10n ** BigInt(fractionDigits);
  const minor =
    BigInt(major) * divisor +
    BigInt(fraction.padEnd(fractionDigits, "0") || "0");
  if (minor > POSTGRES_BIGINT_MAX) {
    throw new TypeError("invalid_money_range");
  }
  return minor.toString();
}

export function formatMinorMoney(
  value: string,
  currencyCode: string,
  locale: string,
): string {
  if (!/^-?(?:0|[1-9]\d{0,18})$/u.test(value)) {
    throw new TypeError("invalid_minor_money");
  }

  const formatter = new Intl.NumberFormat(locale, {
    currency: currencyCode,
    style: "currency",
  });
  const fractionDigits = currencyFractionDigits(currencyCode);
  const divisor = 10n ** BigInt(fractionDigits);
  const minor = BigInt(value);
  if (minor < -POSTGRES_BIGINT_MAX || minor > POSTGRES_BIGINT_MAX) {
    throw new TypeError("invalid_minor_money");
  }
  const absoluteMinor = minor < 0n ? -minor : minor;
  const whole = absoluteMinor / divisor;
  const formattedWhole: bigint | number =
    minor < 0n ? (whole === 0n ? -0 : -whole) : whole;
  const fraction = (absoluteMinor % divisor)
    .toString()
    .padStart(fractionDigits, "0");

  return formatter
    .formatToParts(formattedWhole)
    .map((part) => (part.type === "fraction" ? fraction : part.value))
    .join("");
}

export function minorMoneyToMajorInput(
  value: string,
  currencyCode: string,
): string {
  if (!/^(?:0|[1-9]\d{0,18})$/u.test(value)) {
    throw new TypeError("invalid_minor_money");
  }
  const fractionDigits = currencyFractionDigits(currencyCode);
  if (fractionDigits === 0) {
    return value;
  }
  const padded = value.padStart(fractionDigits + 1, "0");
  return `${padded.slice(0, -fractionDigits)}.${padded.slice(-fractionDigits)}`;
}
