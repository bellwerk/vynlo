import { Button } from "@vynlo/ui-web/components/button";
import { Input } from "@vynlo/ui-web/components/input";

import { setLocale } from "../app/actions/locale";
import type { Locale } from "../i18n/messages";

interface LocaleSwitcherProps {
  readonly activeLocale: Locale;
  readonly label: string;
  readonly localeNames: Readonly<Record<Locale, string>>;
  readonly returnTo: string;
}

export function LocaleSwitcher({
  activeLocale,
  label,
  localeNames,
  returnTo,
}: LocaleSwitcherProps) {
  return (
    <form action={setLocale} className="locale-switcher">
      <Input name="returnTo" type="hidden" value={returnTo} />
      <span className="control-label">{label}</span>
      <div aria-label={label} className="locale-options" role="group">
        {(["en", "fr"] as const).map((locale) => (
          <Button
            aria-pressed={activeLocale === locale}
            key={locale}
            name="locale"
            type="submit"
            value={locale}
          >
            <span aria-hidden="true">{locale.toUpperCase()}</span>
            <span className="sr-only">{localeNames[locale]}</span>
          </Button>
        ))}
      </div>
    </form>
  );
}
