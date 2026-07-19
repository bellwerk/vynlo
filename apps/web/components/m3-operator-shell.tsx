"use client";

import { Fragment, type ReactNode } from "react";

import type { Locale } from "../i18n/messages";
import type { M3Messages } from "../i18n/m3-messages";
import type { OperatorNavigationKey } from "../lib/navigation";
import { OperatorShell, type OperatorWorkspaceOption } from "./operator-shell";

export type M3NavigationKey =
  "leads" | "deals" | "tasks" | "appointments" | "parties";

export type M3WorkspaceOption = OperatorWorkspaceOption;

export interface M3OperatorShellProps {
  readonly attentionCount: number;
  readonly children: ReactNode;
  readonly copy: M3Messages["common"];
  readonly current: M3NavigationKey;
  readonly eyebrow: string;
  readonly jobState?: ReactNode;
  readonly locale: Locale;
  readonly onWorkspaceChange: (workspaceId: string) => void;
  readonly online: boolean;
  readonly previewMode: boolean;
  readonly saveState?: ReactNode;
  readonly selectedWorkspaceId: string;
  readonly summary: string;
  readonly title: string;
  readonly workspaces: readonly M3WorkspaceOption[];
}

function currentModule(current: M3NavigationKey): OperatorNavigationKey {
  return current === "deals" ? "deals" : "people";
}

/** Thin compatibility adapter while M3 route contracts remain unchanged. */
export function M3OperatorShell({
  attentionCount,
  children,
  copy,
  current,
  eyebrow,
  jobState,
  locale,
  onWorkspaceChange,
  online,
  previewMode,
  saveState,
  selectedWorkspaceId,
  summary,
  title,
  workspaces,
}: M3OperatorShellProps) {
  return (
    <OperatorShell
      attentionCount={attentionCount}
      contextLabel={eyebrow}
      copy={copy}
      current={currentModule(current)}
      jobState={jobState}
      locale={locale}
      mainId="m3-main"
      onWorkspaceChange={onWorkspaceChange}
      online={online}
      previewMode={previewMode ? "m3" : null}
      saveState={saveState}
      selectedWorkspaceId={selectedWorkspaceId}
      summary={summary}
      title={title}
      workspaces={workspaces}
    >
      <Fragment key={selectedWorkspaceId || "workspace-loading"}>
        {children}
      </Fragment>
    </OperatorShell>
  );
}
