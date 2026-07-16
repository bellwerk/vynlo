import type { Metadata } from "next";
import { VehicleMediaManagerWorkspace } from "../../../../components/vehicle-media-manager";
import { inventoryIntakeMessages } from "../../../../i18n/inventory-intake-messages";
import { getRequestLocale } from "../../../../i18n/server";
import { vehicleMediaMessages } from "../../../../i18n/vehicle-media-messages";

interface VehicleMediaPageProps {
  readonly params: Promise<Readonly<{ id: string }>>;
  readonly searchParams: Promise<
    Readonly<Record<string, string | string[] | undefined>>
  >;
}

export async function generateMetadata(): Promise<Metadata> {
  const locale = await getRequestLocale();
  return { title: vehicleMediaMessages[locale].heading };
}

export default async function VehicleMediaPage({
  params,
  searchParams,
}: VehicleMediaPageProps) {
  const [locale, route, query] = await Promise.all([
    getRequestLocale(),
    params,
    searchParams,
  ]);
  const previewEnabled =
    process.env.NODE_ENV !== "production" && query.preview === "inventory";
  const requestedWorkspaceId =
    typeof query.workspace === "string" ? query.workspace : undefined;

  return (
    <VehicleMediaManagerWorkspace
      copy={vehicleMediaMessages[locale]}
      inventoryUnitId={route.id}
      locale={locale}
      previewEnabled={previewEnabled}
      uploadCopy={inventoryIntakeMessages[locale]}
      {...(requestedWorkspaceId === undefined ? {} : { requestedWorkspaceId })}
    />
  );
}
