import {
  M3CrmRoutePage,
  type M3SearchParams,
} from "../../../../components/m3-route-page";

export default function NewLeadPage({
  searchParams,
}: {
  readonly searchParams: M3SearchParams;
}) {
  return <M3CrmRoutePage searchParams={searchParams} view="lead-new" />;
}
