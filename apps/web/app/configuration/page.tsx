import {
  M4ConfigurationRoutePage,
  type M4SearchParams,
} from "../../components/m4-route-page";

export default function ConfigurationPage({
  searchParams,
}: {
  readonly searchParams: M4SearchParams;
}) {
  return <M4ConfigurationRoutePage searchParams={searchParams} />;
}
