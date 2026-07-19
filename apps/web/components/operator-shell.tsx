/* Hallmark · genre: modern-minimal · macrostructure: Workbench · design-system: design.md · designed-as-app
 * theme: Vynlo System · tone: clean, exact, neutral · enrichment: none
 * states: default · hover · focus · active · disabled · loading · error · success
 */
"use client";

import type { PlatformPermissionKey } from "@vynlo/auth";
import { Button } from "@vynlo/ui-web/components/button";
import { NativeSelect } from "@vynlo/ui-web/components/native-select";
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@vynlo/ui-web/components/sheet";
import {
  Bell,
  Boxes,
  CircleUserRound,
  Eye,
  FileDown,
  Files,
  Handshake,
  Menu,
  Settings2,
  ShieldCheck,
  UsersRound,
  Wifi,
  WifiOff,
  X,
  type LucideIcon,
} from "lucide-react";
import { usePathname, useSearchParams } from "next/navigation";
import type { ReactNode } from "react";

import type { Locale } from "../i18n/messages";
import {
  OPERATOR_HEADER_STATUS_COPY,
  operatorNavigationHref,
  safeOperatorSearchParameters,
  useOperatorAccountContext,
  useOperatorOnlineStatus,
  useOperatorShellPermissions,
  type OperatorPreviewMode,
} from "../hooks/use-operator-shell-context";
import {
  filterNavigation,
  operatorNavigation,
  type OperatorNavigationKey,
} from "../lib/navigation";
import { LocaleSwitcher } from "./locale-switcher";
import { ThemeSwitcher } from "./theme-switcher";

export interface OperatorWorkspaceOption {
  readonly id: string;
  readonly name: string;
}

export interface OperatorShellCopy {
  readonly appName: string;
  readonly attention: string;
  readonly environment: string;
  readonly localeLabel: string;
  readonly localeNames: Readonly<Record<Locale, string>>;
  readonly navigationLabel: string;
  readonly skipToContent: string;
  readonly workspaceLabel: string;
}

export type { OperatorPreviewMode } from "../hooks/use-operator-shell-context";

export interface OperatorShellProps {
  readonly attentionCount: number;
  readonly children: ReactNode;
  readonly contextLabel?: string;
  readonly copy: OperatorShellCopy;
  readonly current: OperatorNavigationKey;
  readonly grantedPermissions?: ReadonlySet<PlatformPermissionKey>;
  readonly jobState?: ReactNode;
  readonly locale: Locale;
  readonly mainId: string;
  readonly onWorkspaceChange: (workspaceId: string) => void;
  readonly online?: boolean;
  readonly previewMode: OperatorPreviewMode;
  readonly saveState?: ReactNode;
  readonly selectedWorkspaceId: string;
  readonly summary: string;
  readonly title: string;
  readonly workspaces: readonly OperatorWorkspaceOption[];
}

const iconByKey: Readonly<Record<OperatorNavigationKey, LucideIcon>> = {
  configuration: Settings2,
  deals: Handshake,
  documents: Files,
  exports: FileDown,
  inventory: Boxes,
  people: UsersRound,
  system: ShieldCheck,
};

const noOperatorPermissions: ReadonlySet<PlatformPermissionKey> = new Set();
const headerStatusClass =
  "inline-flex min-h-7 items-center gap-1.5 rounded-full border border-border bg-card px-2.5 text-xs font-semibold text-muted-foreground";

const navigationCopy: Readonly<
  Record<
    Locale,
    Readonly<
      Record<
        OperatorNavigationKey | "close" | "more" | "moreDescription",
        string
      >
    >
  >
> = {
  en: {
    close: "Close navigation",
    configuration: "Configuration",
    deals: "Deals",
    documents: "Documents",
    exports: "Exports",
    inventory: "Inventory",
    more: "More",
    moreDescription: "Configuration, exports, and system status",
    people: "People",
    system: "System",
  },
  fr: {
    close: "Fermer la navigation",
    configuration: "Configuration",
    deals: "Dossiers",
    documents: "Documents",
    exports: "Exports",
    inventory: "Inventaire",
    more: "Plus",
    moreDescription: "Configuration, exports et état du système",
    people: "Clients",
    system: "Système",
  },
};

export function OperatorShell({
  attentionCount,
  children,
  contextLabel,
  copy,
  current,
  grantedPermissions,
  jobState,
  locale,
  mainId,
  onWorkspaceChange,
  online,
  previewMode,
  saveState,
  selectedWorkspaceId,
  summary,
  title,
  workspaces,
}: OperatorShellProps) {
  const pathname = usePathname();
  const searchParameters = useSearchParams();
  const labels = navigationCopy[locale];
  const statusLabels = OPERATOR_HEADER_STATUS_COPY[locale];
  const accountContext = useOperatorAccountContext(previewMode);
  const resolvedOnline = useOperatorOnlineStatus(online);
  const permissions = useOperatorShellPermissions({
    explicitPermissions: grantedPermissions,
    previewMode,
    selectedWorkspaceId,
  });
  const safeLocaleSearchParameters =
    safeOperatorSearchParameters(searchParameters);
  const safeLocaleQuery = safeLocaleSearchParameters.toString();
  const localeReturnTo = safeLocaleQuery
    ? `${pathname}?${safeLocaleQuery}`
    : pathname;
  const visibleNavigation = filterNavigation(
    operatorNavigation,
    permissions ?? noOperatorPermissions,
  );
  const navigationHref = (href: string, key: OperatorNavigationKey) =>
    operatorNavigationHref({
      href,
      key,
      previewMode,
      searchParameters,
    });
  const primaryNavigation = visibleNavigation.filter(
    ({ mobilePlacement }) => mobilePlacement === "primary",
  );
  const moreNavigation = visibleNavigation.filter(
    ({ mobilePlacement }) => mobilePlacement === "more",
  );
  const moreIsActive = moreNavigation.some(({ key }) => key === current);
  const accountLabel =
    accountContext === "authenticated"
      ? statusLabels.authenticated
      : accountContext === "checking"
        ? statusLabels.checking
        : accountContext === "preview"
          ? statusLabels.preview
          : statusLabels.signedOut;
  const AccountIcon = accountContext === "preview" ? Eye : CircleUserRound;
  const ConnectivityIcon = resolvedOnline ? Wifi : WifiOff;

  return (
    <div className="vynlo-shell" data-vynlo-ui="app-shell">
      <nav aria-label={copy.skipToContent} className="contents">
        <a className="skip-link" href={`#${mainId}`}>
          {copy.skipToContent}
        </a>
      </nav>

      <aside className="vynlo-shell__sidebar">
        <a className="vynlo-shell__brand" href="/" aria-label={copy.appName}>
          <span aria-hidden="true" className="vynlo-shell__brand-mark">
            V
          </span>
          <span>{copy.appName}</span>
        </a>

        <nav
          aria-label={copy.navigationLabel}
          className="vynlo-shell__desktop-nav"
        >
          <ul>
            {visibleNavigation.map((item) => {
              const Icon = iconByKey[item.icon];
              const active = item.key === current;
              return (
                <li key={item.key}>
                  <a
                    aria-current={active ? "page" : undefined}
                    data-active={active}
                    href={navigationHref(item.href, item.key)}
                  >
                    <Icon aria-hidden="true" size={18} strokeWidth={1.8} />
                    <span>{labels[item.translationKey]}</span>
                  </a>
                </li>
              );
            })}
          </ul>
        </nav>

        <div className="vynlo-shell__environment">
          <span>{copy.environment}</span>
          <strong>
            <span aria-hidden="true" className="vynlo-shell__status-dot" />
            {attentionCount} {copy.attention.toLocaleLowerCase(locale)}
          </strong>
        </div>
      </aside>

      <nav
        aria-label={copy.navigationLabel}
        className="vynlo-shell__mobile-nav"
      >
        <ul>
          {primaryNavigation.map((item) => {
            const Icon = iconByKey[item.icon];
            const active = item.key === current;
            return (
              <li key={item.key}>
                <a
                  aria-current={active ? "page" : undefined}
                  data-active={active}
                  href={navigationHref(item.href, item.key)}
                >
                  <Icon aria-hidden="true" size={20} strokeWidth={1.8} />
                  <span>{labels[item.translationKey]}</span>
                </a>
              </li>
            );
          })}
          <li>
            <Sheet>
              <SheetTrigger asChild>
                <Button
                  aria-current={moreIsActive ? "page" : undefined}
                  className="vynlo-shell__more-trigger"
                  data-active={moreIsActive}
                  data-vynlo-ui="mobile-more-trigger"
                  type="button"
                  variant="ghost"
                >
                  <Menu aria-hidden="true" size={20} strokeWidth={1.8} />
                  <span>{labels.more}</span>
                </Button>
              </SheetTrigger>
              <SheetContent
                className="vynlo-shell__more-sheet"
                showCloseButton={false}
                side="bottom"
              >
                <SheetHeader>
                  <SheetTitle>{labels.more}</SheetTitle>
                  <SheetDescription>{labels.moreDescription}</SheetDescription>
                  <SheetClose asChild>
                    <Button
                      aria-label={labels.close}
                      className="vynlo-shell__sheet-close"
                      size="icon"
                      type="button"
                      variant="ghost"
                    >
                      <X aria-hidden="true" />
                    </Button>
                  </SheetClose>
                </SheetHeader>
                <nav aria-label={labels.more}>
                  <ul className="vynlo-shell__more-list">
                    {moreNavigation.map((item) => {
                      const Icon = iconByKey[item.icon];
                      const active = item.key === current;
                      return (
                        <li key={item.key}>
                          <SheetClose asChild>
                            <a
                              aria-current={active ? "page" : undefined}
                              data-active={active}
                              href={navigationHref(item.href, item.key)}
                            >
                              <Icon
                                aria-hidden="true"
                                size={20}
                                strokeWidth={1.8}
                              />
                              <span>{labels[item.translationKey]}</span>
                            </a>
                          </SheetClose>
                        </li>
                      );
                    })}
                  </ul>
                </nav>
              </SheetContent>
            </Sheet>
          </li>
        </ul>
      </nav>

      <div className="vynlo-shell__workspace">
        <header className="vynlo-shell__topbar">
          <a
            className="vynlo-shell__mobile-brand"
            href="/"
            aria-label={copy.appName}
          >
            <span aria-hidden="true">V</span>
          </a>

          <label className="vynlo-shell__workspace-switcher">
            <span className="sr-only">{copy.workspaceLabel}</span>
            <NativeSelect
              aria-label={copy.workspaceLabel}
              className="h-11 min-h-11 w-full rounded-[var(--radius-control)] bg-[var(--surface)] font-semibold"
              disabled={workspaces.length < 2}
              onChange={(event) => onWorkspaceChange(event.target.value)}
              value={selectedWorkspaceId}
            >
              {workspaces.map((workspace) => (
                <option key={workspace.id} value={workspace.id}>
                  {workspace.name}
                </option>
              ))}
            </NativeSelect>
          </label>

          <ThemeSwitcher locale={locale} />
          <LocaleSwitcher
            activeLocale={locale}
            label={copy.localeLabel}
            localeNames={copy.localeNames}
            returnTo={localeReturnTo}
          />

          <div
            aria-label={statusLabels.group}
            aria-live="polite"
            className="order-4 col-span-full flex min-w-0 flex-wrap items-center justify-end gap-2 md:order-none md:ml-2"
            role="status"
          >
            <span className={headerStatusClass} data-state={accountContext}>
              <AccountIcon aria-hidden="true" size={15} strokeWidth={1.8} />
              <span className="sr-only">{statusLabels.account}: </span>
              {accountLabel}
            </span>
            <span
              className={headerStatusClass}
              data-state={resolvedOnline ? "online" : "offline"}
            >
              <ConnectivityIcon
                aria-hidden="true"
                size={15}
                strokeWidth={1.8}
              />
              <span className="sr-only">{statusLabels.connectivity}: </span>
              {resolvedOnline ? statusLabels.online : statusLabels.offline}
            </span>
            <span
              className={headerStatusClass}
              data-state={attentionCount > 0 ? "attention" : "idle"}
            >
              <Bell aria-hidden="true" size={15} strokeWidth={1.8} />
              {attentionCount} {copy.attention.toLocaleLowerCase(locale)}
            </span>
            {saveState ? (
              <div className={headerStatusClass} data-slot="save-state">
                {saveState}
              </div>
            ) : null}
            {jobState ? (
              <div className={headerStatusClass} data-slot="job-state">
                {jobState}
              </div>
            ) : null}
          </div>
        </header>

        <main className="vynlo-shell__main" id={mainId} tabIndex={-1}>
          <header className="vynlo-shell__page-header">
            <div>
              {contextLabel ? <p>{contextLabel}</p> : null}
              <h1>{title}</h1>
            </div>
            <p>{summary}</p>
          </header>
          {children}
        </main>
      </div>
    </div>
  );
}
