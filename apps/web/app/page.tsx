import type { PlatformPermissionKey } from "@vynlo/auth";
import { Button } from "@vynlo/ui-web/components/button";
import { ArrowUpRight, CircleDot, ShieldCheck } from "lucide-react";
import { LocaleSwitcher } from "../components/locale-switcher";
import { WorkspaceSwitcher } from "../components/workspace-switcher";
import { messages } from "../i18n/messages";
import { getRequestLocale } from "../i18n/server";
import { applicationNavigation, filterNavigation } from "../lib/navigation";

export default async function HomePage() {
  const locale = await getRequestLocale();
  const copy = messages[locale];
  const grantedPermissions = new Set<PlatformPermissionKey>();
  const navigation = filterNavigation(
    applicationNavigation,
    grantedPermissions,
  );

  return (
    <div className="app-frame">
      <a className="skip-link" href="#main">
        {copy.skipToContent}
      </a>

      <header className="shell-header">
        <div className="topbar">
          <a className="brand" href="/" aria-label={copy.brandHome}>
            <span className="brand-mark" aria-hidden="true">
              V
            </span>
            <span>Vynlo</span>
          </a>

          <div className="shell-controls">
            <WorkspaceSwitcher
              label={copy.workspaceLabel}
              options={[{ id: "foundation", name: copy.currentWorkspace }]}
              selectedWorkspaceId="foundation"
            />
            <LocaleSwitcher
              activeLocale={locale}
              label={copy.localeLabel}
              localeNames={copy.localeNames}
              returnTo="/"
            />
          </div>
        </div>

        <nav aria-label={copy.navigationLabel} className="shell-navigation">
          <ul className="nav-list">
            {navigation.map((item) => (
              <li key={item.key}>
                <a
                  aria-current={item.key === "overview" ? "page" : undefined}
                  href={item.href}
                >
                  {copy.navigation[item.key]}
                </a>
              </li>
            ))}
          </ul>
          <div className="environment-badge">
            <CircleDot aria-hidden="true" size={14} /> {copy.environment}
          </div>
        </nav>
      </header>

      <main id="main" tabIndex={-1}>
        <section
          aria-labelledby="workspace-readiness-title"
          className="workspace-overview"
          id="overview"
        >
          <div className="workspace-heading">
            <p className="eyebrow">
              <span>{copy.stage}</span> {copy.foundation}
            </p>
            <h1 id="workspace-readiness-title">{copy.heading}</h1>
            <p className="workspace-summary">{copy.introduction}</p>
          </div>

          <div aria-label={copy.statusLabel} className="status-list">
            {copy.statusRows.map(([title, description, status], index) => (
              <article className="status-row" key={title}>
                <span aria-hidden="true" className="row-index">
                  {String(index + 1).padStart(2, "0")}
                </span>
                <div>
                  <h2>{title}</h2>
                  <p>{description}</p>
                </div>
                <span className="status-value">
                  {index < 2 ? (
                    <ShieldCheck aria-hidden="true" size={16} />
                  ) : null}
                  {status}
                </span>
              </article>
            ))}
          </div>

          <div className="workspace-actions">
            <Button asChild>
              <a href="/login">
                {copy.accessAction}{" "}
                <ArrowUpRight aria-hidden="true" size={18} />
              </a>
            </Button>
            <Button asChild variant="outline">
              <a href="/operations">{copy.operationsAction}</a>
            </Button>
            <a className="text-link" href="/health">
              {copy.healthAction}
            </a>
            <a className="text-link" href="/api/v1/health/ready">
              {copy.readinessAction}
            </a>
          </div>
        </section>
      </main>

      <footer>
        <span>{copy.footer[0]}</span>
        <span>{copy.footer[1]}</span>
      </footer>
    </div>
  );
}
