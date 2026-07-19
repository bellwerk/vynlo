import { getRequestLocale } from "../i18n/server";
import {
  M4DocumentWorkbench,
  type M4DocumentView,
} from "./m4-document-workbench";
import { M4ConfigurationWorkbench } from "./m4-configuration-workbench";
import { M4ExportsWorkbench } from "./m4-exports-workbench";

export type M4SearchParams = Promise<
  Readonly<Record<string, string | string[] | undefined>>
>;
export type M4EntityParams = Promise<Readonly<{ id: string }>>;

function previewEnabled(
  query: Readonly<Record<string, string | string[] | undefined>>,
) {
  return process.env.NODE_ENV !== "production" && query.preview === "m4";
}

export async function M4DocumentRoutePage({
  params,
  searchParams,
  view,
}: {
  readonly params?: M4EntityParams;
  readonly searchParams: M4SearchParams;
  readonly view: M4DocumentView;
}) {
  const [locale, query, route] = await Promise.all([
    getRequestLocale(),
    searchParams,
    params ?? Promise.resolve(undefined),
  ]);
  return (
    <M4DocumentWorkbench
      {...(route ? { documentId: route.id } : {})}
      locale={locale}
      previewMode={previewEnabled(query)}
      view={view}
    />
  );
}

export async function M4ConfigurationRoutePage({
  searchParams,
}: {
  readonly searchParams: M4SearchParams;
}) {
  const [locale, query] = await Promise.all([getRequestLocale(), searchParams]);
  return (
    <M4ConfigurationWorkbench
      locale={locale}
      previewMode={previewEnabled(query)}
    />
  );
}

export async function M4ExportsRoutePage({
  searchParams,
}: {
  readonly searchParams: M4SearchParams;
}) {
  const [locale, query] = await Promise.all([getRequestLocale(), searchParams]);
  return (
    <M4ExportsWorkbench locale={locale} previewMode={previewEnabled(query)} />
  );
}
