import { OperationsWorkbench } from "../../components/operations-workbench";
import { messages } from "../../i18n/messages";
import { getRequestLocale } from "../../i18n/server";

export default async function OperationsPage() {
  const locale = await getRequestLocale();
  return (
    <main id="main">
      <OperationsWorkbench copy={messages[locale].operations} locale={locale} />
    </main>
  );
}
