import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getRequestLocale } from "../../../i18n/server";
import { DesignSystemGallery } from "./design-system-gallery";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Vynlo System UI",
};

export default async function DesignSystemPage() {
  if (process.env.NODE_ENV === "production") {
    notFound();
  }

  const locale = await getRequestLocale();

  return <DesignSystemGallery locale={locale} />;
}
