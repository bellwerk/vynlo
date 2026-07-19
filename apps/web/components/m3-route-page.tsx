import { getRequestLocale } from "../i18n/server";
import { M3CrmWorkbench, type M3CrmView } from "./m3-crm-workbench";
import { M3DealWorkbench, type M3DealView } from "./m3-deal-workbench";

export type M3SearchParams = Promise<
  Readonly<Record<string, string | string[] | undefined>>
>;
export type M3EntityParams = Promise<Readonly<{ id: string }>>;

function previewEnabled(
  query: Readonly<Record<string, string | string[] | undefined>>,
) {
  return process.env.NODE_ENV !== "production" && query.preview === "m3";
}

export async function M3CrmRoutePage({
  params,
  searchParams,
  view,
}: {
  readonly params?: M3EntityParams | undefined;
  readonly searchParams: M3SearchParams;
  readonly view: M3CrmView;
}) {
  const [locale, query, route] = await Promise.all([
    getRequestLocale(),
    searchParams,
    params ?? Promise.resolve(undefined),
  ]);
  return (
    <M3CrmWorkbench
      {...(route === undefined ? {} : { entityId: route.id })}
      locale={locale}
      previewMode={previewEnabled(query)}
      view={view}
    />
  );
}

export async function M3DealRoutePage({
  params,
  searchParams,
  view,
}: {
  readonly params?: M3EntityParams | undefined;
  readonly searchParams: M3SearchParams;
  readonly view: M3DealView;
}) {
  const [locale, query, route] = await Promise.all([
    getRequestLocale(),
    searchParams,
    params ?? Promise.resolve(undefined),
  ]);
  return (
    <M3DealWorkbench
      {...(route === undefined ? {} : { dealId: route.id })}
      locale={locale}
      previewMode={previewEnabled(query)}
      view={view}
    />
  );
}
