"use client";

import { useSyncExternalStore } from "react";
import { Monitor, Moon, Sun } from "lucide-react";
import { useTheme } from "next-themes";
import { Button } from "@vynlo/ui-web/components/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@vynlo/ui-web/components/dropdown-menu";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@vynlo/ui-web/components/tooltip";
import { cn } from "@vynlo/ui-web/lib/utils";
import type { ThemeMode } from "./theme-provider";

const labels = {
  en: {
    choose: "Choose theme",
    dark: "Dark",
    light: "Light",
    system: "System",
    theme: "Theme",
  },
  fr: {
    choose: "Choisir le thème",
    dark: "Sombre",
    light: "Clair",
    system: "Système",
    theme: "Thème",
  },
} as const;

const subscribeToHydration = () => () => undefined;

export function ThemeSwitcher({
  className,
  locale,
}: {
  className?: string;
  locale: "en" | "fr";
}) {
  const { resolvedTheme, setTheme, theme } = useTheme();
  const mounted = useSyncExternalStore(
    subscribeToHydration,
    () => true,
    () => false,
  );
  const text = labels[locale];
  const themeOptions: ReadonlyArray<{
    icon: typeof Monitor;
    label: string;
    value: ThemeMode;
  }> = [
    { icon: Monitor, label: text.system, value: "system" },
    { icon: Sun, label: text.light, value: "light" },
    { icon: Moon, label: text.dark, value: "dark" },
  ];

  const selectedTheme: ThemeMode =
    mounted && (theme === "light" || theme === "dark" || theme === "system")
      ? theme
      : "system";
  const ActiveIcon =
    mounted && resolvedTheme === "dark"
      ? Moon
      : mounted && resolvedTheme === "light"
        ? Sun
        : Monitor;

  return (
    <DropdownMenu>
      <Tooltip>
        <TooltipTrigger asChild>
          <DropdownMenuTrigger asChild>
            <Button
              aria-label={text.choose}
              className={cn("size-11 rounded-full", className)}
              data-vynlo-ui="theme-trigger"
              size="icon"
              type="button"
              variant="ghost"
            >
              <ActiveIcon aria-hidden="true" />
            </Button>
          </DropdownMenuTrigger>
        </TooltipTrigger>
        <TooltipContent>{text.theme}</TooltipContent>
      </Tooltip>
      <DropdownMenuContent align="end" className="min-w-48">
        <DropdownMenuLabel>{text.theme}</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuRadioGroup value={selectedTheme} onValueChange={setTheme}>
          {themeOptions.map(({ icon: Icon, label, value }) => (
            <DropdownMenuRadioItem
              className="min-h-11"
              key={value}
              value={value}
            >
              <Icon aria-hidden="true" />
              <span>{label}</span>
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
