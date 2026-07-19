import type { Locale } from "../i18n/messages";

export interface LocalizedDealOption {
  readonly key: string;
  readonly labels: Readonly<Record<Locale, string>>;
}

export function localizedDealOptionLabel(
  options: readonly LocalizedDealOption[],
  key: string,
  locale: Locale,
  fallback: string,
): string {
  const labels = options.find((option) => option.key === key)?.labels;
  return labels?.[locale] ?? labels?.en ?? labels?.fr ?? fallback;
}
