import {
  M3DealRoutePage,
  type M3SearchParams,
} from "../../../components/m3-route-page";

export default function NewDealPage({
  searchParams,
}: {
  readonly searchParams: M3SearchParams;
}) {
  return <M3DealRoutePage searchParams={searchParams} view="deal-new" />;
}
