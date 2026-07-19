"use client";

import type { ComponentProps } from "react";
import { ThemeProvider as NextThemesProvider } from "next-themes";

export type { ThemeMode } from "@vynlo/design-tokens";

type ThemeProviderProps = Omit<
  ComponentProps<typeof NextThemesProvider>,
  "attribute" | "defaultTheme" | "enableSystem" | "storageKey"
>;

export function ThemeProvider({ children, ...props }: ThemeProviderProps) {
  return (
    <NextThemesProvider
      attribute="class"
      defaultTheme="system"
      disableTransitionOnChange
      enableColorScheme
      enableSystem
      storageKey="vynlo-theme"
      {...props}
    >
      {children}
    </NextThemesProvider>
  );
}
