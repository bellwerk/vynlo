import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { PwaLifecycle } from "../components/pwa-lifecycle";
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
  colorScheme: "light",
  themeColor: "#17251f",
  width: "device-width",
};

export default async function RootLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  const locale = await getRequestLocale();

  return (
    <html lang={locale}>
      <body>
        <PwaLifecycle messages={messages[locale].pwa} />
        {children}
      </body>
    </html>
  );
}
