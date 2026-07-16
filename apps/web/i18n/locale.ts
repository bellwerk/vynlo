import { defaultLocale, type Locale } from "./messages";

export const localeCookieName = "vynlo_locale";
export const supportedLocales = [
  "en",
  "fr",
] as const satisfies readonly Locale[];

export function isSupportedLocale(value: unknown): value is Locale {
  return supportedLocales.some((locale) => locale === value);
}

export function resolveLocale(value: unknown): Locale {
  return isSupportedLocale(value) ? value : defaultLocale;
}

export function sanitizeReturnPath(value: unknown): string {
  if (
    typeof value !== "string" ||
    !value.startsWith("/") ||
    value.startsWith("//") ||
    value.includes("\\") ||
    value.includes("\0")
  ) {
    return "/";
  }

  return value;
}
