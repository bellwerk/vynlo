import {
  M3CrmRoutePage,
  type M3EntityParams,
  type M3SearchParams,
} from "../../../../components/m3-route-page";

export default function PartyDetailPage({
  params,
  searchParams,
}: {
  readonly params: M3EntityParams;
  readonly searchParams: M3SearchParams;
}) {
  return (
    <M3CrmRoutePage
      params={params}
      searchParams={searchParams}
      view="party-detail"
    />
  );
}
