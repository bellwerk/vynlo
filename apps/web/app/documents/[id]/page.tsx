import {
  M4DocumentRoutePage,
  type M4EntityParams,
  type M4SearchParams,
} from "../../../components/m4-route-page";

export default function DocumentDetailPage({
  params,
  searchParams,
}: {
  readonly params: M4EntityParams;
  readonly searchParams: M4SearchParams;
}) {
  return (
    <M4DocumentRoutePage
      params={params}
      searchParams={searchParams}
      view="detail"
    />
  );
}
