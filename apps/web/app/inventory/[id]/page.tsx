import type { Metadata } from "next";
import { InventoryOperations } from "../../../components/inventory-operations";
import { inventoryOperationsMessages } from "../../../i18n/inventory-operations-messages";
import { getRequestLocale } from "../../../i18n/server";

interface InventoryOperationsPageProps {
  readonly params: Promise<Readonly<{ id: string }>>;
  readonly searchParams: Promise<
    Readonly<Record<string, string | string[] | undefined>>
  >;
}

export async function generateMetadata(): Promise<Metadata> {
  const locale = await getRequestLocale();
  return { title: inventoryOperationsMessages[locale].headingFallback };
}

export default async function InventoryOperationsPage({
  params,
  searchParams,
}: InventoryOperationsPageProps) {
  const [locale, route, query] = await Promise.all([
    getRequestLocale(),
    params,
    searchParams,
  ]);
  const previewMode =
    process.env.NODE_ENV !== "production" && query.preview === "inventory";
  const requestedWorkspaceId =
    typeof query.workspace === "string" ? query.workspace : undefined;

  return (
    <InventoryOperations
      copy={inventoryOperationsMessages[locale]}
      inventoryUnitId={route.id}
      locale={locale}
      previewMode={previewMode}
      {...(requestedWorkspaceId === undefined ? {} : { requestedWorkspaceId })}
    />
  );
}
