import {
  M3CrmRoutePage,
  type M3SearchParams,
} from "../../../components/m3-route-page";

export default function AppointmentsPage({
  searchParams,
}: {
  readonly searchParams: M3SearchParams;
}) {
  return <M3CrmRoutePage searchParams={searchParams} view="appointments" />;
}
