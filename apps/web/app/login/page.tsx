import { ArrowLeft } from "lucide-react";
import { AuthAccess } from "../../components/auth-access";
import { messages } from "../../i18n/messages";
import { getRequestLocale } from "../../i18n/server";
import { parseWorkspaceInvitationContext } from "../../lib/workspace-invitation-client";

interface LoginPageProps {
  readonly searchParams: Promise<
    Readonly<Record<string, string | readonly string[] | undefined>>
  >;
}

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const locale = await getRequestLocale();
  const copy = messages[locale].auth;
  const query = await searchParams;
  const invitation = parseWorkspaceInvitationContext(query);

  return (
    <main className="access-page" id="main">
      <a className="back-link" href="/">
        <ArrowLeft aria-hidden="true" size={17} /> {copy.backAction}
      </a>
      <section aria-labelledby="access-title" className="access-panel">
        <header>
          <p className="eyebrow">
            <span>{copy.stage}</span> {copy.accessLabel}
          </p>
          <h1 id="access-title">{copy.heading}</h1>
          <p>{copy.introduction}</p>
        </header>
        <AuthAccess
          copy={copy.form}
          hasInvalidInvitationContext={invitation.invalid}
          {...(invitation.context ? { invitation: invitation.context } : {})}
        />
      </section>
    </main>
  );
}
