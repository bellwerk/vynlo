import type { Metadata } from "next";
import { InventoryWorkbench } from "../../components/inventory-workbench";
import { inventoryMessages } from "../../i18n/inventory-messages";
import { getRequestLocale } from "../../i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const locale = await getRequestLocale();
  return { title: inventoryMessages[locale].heading };
}

interface InventoryPageProps {
  readonly searchParams: Promise<
    Readonly<Record<string, string | string[] | undefined>>
  >;
}

export default async function InventoryPage({
  searchParams,
}: InventoryPageProps) {
  const [locale, parameters] = await Promise.all([
    getRequestLocale(),
    searchParams,
  ]);
  const previewMode =
    process.env.NODE_ENV !== "production" && parameters.preview === "inventory";

  return (
    <InventoryWorkbench
      copy={inventoryMessages[locale]}
      locale={locale}
      previewMode={previewMode}
    />
  );
}
