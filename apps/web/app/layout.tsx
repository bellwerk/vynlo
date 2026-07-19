import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { Toaster } from "@vynlo/ui-web/components/sonner";
import { TooltipProvider } from "@vynlo/ui-web/components/tooltip";
import { PwaLifecycle } from "../components/pwa-lifecycle";
import { ThemeProvider } from "../components/theme-provider";
import { messages } from "../i18n/messages";
import { getRequestLocale } from "../i18n/server";
import "./globals.css";

export const metadata: Metadata = {
  applicationName: "Vynlo",
  description: "Mobile-first dealership operations platform",
  icons: {
    apple: "/icons/vynlo-192.svg",
    icon: "/icons/vynlo-192.svg",
  },
  manifest: "/manifest.webmanifest",
  title: {
    default: "Vynlo",
    template: "%s · Vynlo",
  },
};

export const viewport: Viewport = {
  colorScheme: "light dark",
  themeColor: [
    { color: "#f5f5f7", media: "(prefers-color-scheme: light)" },
    { color: "#0b0b0c", media: "(prefers-color-scheme: dark)" },
  ],
  width: "device-width",
};

export default async function RootLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  const locale = await getRequestLocale();

  return (
    <html lang={locale} suppressHydrationWarning>
      <body>
        <ThemeProvider>
          <TooltipProvider delayDuration={800}>
            <PwaLifecycle messages={messages[locale].pwa} />
            {children}
            <Toaster closeButton position="bottom-right" richColors />
          </TooltipProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
