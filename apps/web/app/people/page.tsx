import {
  M3CrmRoutePage,
  type M3SearchParams,
} from "../../components/m3-route-page";

export default function PeoplePage({
  searchParams,
}: {
  readonly searchParams: M3SearchParams;
}) {
  return <M3CrmRoutePage searchParams={searchParams} view="leads" />;
}
