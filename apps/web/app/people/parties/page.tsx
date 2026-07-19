import {
  M3CrmRoutePage,
  type M3SearchParams,
} from "../../../components/m3-route-page";

export default function PartiesPage({
  searchParams,
}: {
  readonly searchParams: M3SearchParams;
}) {
  return <M3CrmRoutePage searchParams={searchParams} view="parties" />;
}
