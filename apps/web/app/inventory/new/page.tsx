import type { Metadata } from "next";
import { InventoryIntake } from "../../../components/inventory-intake";
import { inventoryIntakeMessages } from "../../../i18n/inventory-intake-messages";
import { getRequestLocale } from "../../../i18n/server";

interface InventoryIntakePageProps {
  readonly searchParams: Promise<
    Readonly<Record<string, string | string[] | undefined>>
  >;
}

export async function generateMetadata(): Promise<Metadata> {
  const locale = await getRequestLocale();
  return { title: inventoryIntakeMessages[locale].heading };
}

export default async function InventoryIntakePage({
  searchParams,
}: InventoryIntakePageProps) {
  const [locale, parameters] = await Promise.all([
    getRequestLocale(),
    searchParams,
  ]);
  const previewMode =
    process.env.NODE_ENV !== "production" && parameters.preview === "inventory";

  return (
    <InventoryIntake
      copy={inventoryIntakeMessages[locale]}
      locale={locale}
      previewMode={previewMode}
    />
  );
}
