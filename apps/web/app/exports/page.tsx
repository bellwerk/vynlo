import {
  M4ExportsRoutePage,
  type M4SearchParams,
} from "../../components/m4-route-page";

export default function ExportsPage({
  searchParams,
}: {
  readonly searchParams: M4SearchParams;
}) {
  return <M4ExportsRoutePage searchParams={searchParams} />;
}
