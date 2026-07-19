import {
  M4DocumentRoutePage,
  type M4SearchParams,
} from "../../components/m4-route-page";

export default function DocumentsPage({
  searchParams,
}: {
  readonly searchParams: M4SearchParams;
}) {
  return <M4DocumentRoutePage searchParams={searchParams} view="list" />;
}
