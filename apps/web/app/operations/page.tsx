import { OperationsWorkbench } from "../../components/operations-workbench";
import { m4Messages } from "../../i18n/m4-messages";
import { messages } from "../../i18n/messages";
import { getRequestLocale } from "../../i18n/server";

export default async function OperationsPage() {
  const locale = await getRequestLocale();
  return (
    <OperationsWorkbench
      copy={messages[locale].operations}
      locale={locale}
      shellCopy={m4Messages[locale].common}
    />
  );
}
