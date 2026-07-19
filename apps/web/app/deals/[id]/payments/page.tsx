import {
  M3DealRoutePage,
  type M3EntityParams,
  type M3SearchParams,
} from "../../../../components/m3-route-page";

export default function DealPaymentsPage({
  params,
  searchParams,
}: {
  readonly params: M3EntityParams;
  readonly searchParams: M3SearchParams;
}) {
  return (
    <M3DealRoutePage
      params={params}
      searchParams={searchParams}
      view="payments"
    />
  );
}
