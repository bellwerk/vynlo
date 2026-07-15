import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  applicationName: "Vynlo",
  description: "Mobile-first dealership operations platform",
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

export default function RootLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
