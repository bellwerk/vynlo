import type { Locale } from "../i18n/messages";

export function formatM3MinorAmount(
  amountMinor: string,
  currencyCode: string,
  locale: Locale,
): string {
  if (!/^-?(?:0|[1-9][0-9]*)$/u.test(amountMinor)) {
    throw new TypeError("invalid_minor_amount");
  }
  const normalizedCurrency = currencyCode.trim().toUpperCase();
  if (!/^[A-Z]{3}$/u.test(normalizedCurrency)) {
    throw new TypeError("invalid_currency_code");
  }
  const fractionDigits =
    new Intl.NumberFormat("en", {
      currency: normalizedCurrency,
      style: "currency",
    }).resolvedOptions().maximumFractionDigits ?? 2;
  const negative = amountMinor.startsWith("-") && amountMinor !== "-0";
  const digits = amountMinor
    .replaceAll(/[^0-9]/gu, "")
    .padStart(fractionDigits + 1, "0");
  const majorDigits =
    fractionDigits === 0 ? digits : digits.slice(0, -fractionDigits);
  const major = majorDigits.replace(
    /\B(?=(\d{3})+(?!\d))/gu,
    locale === "fr" ? " " : ",",
  );
  const decimal =
    fractionDigits === 0
      ? ""
      : `${locale === "fr" ? "," : "."}${digits.slice(-fractionDigits)}`;
  return `${negative ? "−" : ""}${major}${decimal} ${normalizedCurrency}`;
}
