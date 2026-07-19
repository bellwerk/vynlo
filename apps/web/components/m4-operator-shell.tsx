"use client";

import { Fragment, type ReactNode } from "react";

import type { Locale } from "../i18n/messages";
import type { M4Messages } from "../i18n/m4-messages";
import type { OperatorNavigationKey } from "../lib/navigation";
import { OperatorShell, type OperatorWorkspaceOption } from "./operator-shell";

export type M4NavigationKey =
  "people" | "deals" | "documents" | "configuration" | "exports";

export type M4WorkspaceOption = OperatorWorkspaceOption;

export interface M4OperatorShellProps {
  readonly attentionCount: number;
  readonly children: ReactNode;
  readonly copy: M4Messages["common"];
  readonly current: M4NavigationKey;
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
  readonly workspaces: readonly M4WorkspaceOption[];
}

function currentModule(current: M4NavigationKey): OperatorNavigationKey {
  return current;
}

/** Thin compatibility adapter while M4 route contracts remain unchanged. */
export function M4OperatorShell({
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
}: M4OperatorShellProps) {
  return (
    <OperatorShell
      attentionCount={attentionCount}
      contextLabel={eyebrow}
      copy={copy}
      current={currentModule(current)}
      jobState={jobState}
      locale={locale}
      mainId="m4-main"
      onWorkspaceChange={onWorkspaceChange}
      online={online}
      previewMode={previewMode ? "m4" : null}
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
