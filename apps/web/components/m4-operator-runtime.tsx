"use client";

import { AlertTriangle, LoaderCircle, WifiOff } from "lucide-react";
import { useRouter } from "next/navigation";
import { Button } from "@vynlo/ui-web";
import {
  type ReactNode,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";

import { useOperatorOnlineStatus } from "../hooks/use-operator-shell-context";
import type { Locale } from "../i18n/messages";
import type { M4Messages } from "../i18n/m4-messages";
import type { M4ApiContext } from "../lib/m4-api-client";
import { getBrowserSupabase } from "../lib/supabase-browser";
import {
  M4OperatorShell,
  type M4NavigationKey,
  type M4WorkspaceOption,
} from "./m4-operator-shell";

export const M4_PREVIEW_WORKSPACE_ID = "10000000-0000-4000-8000-000000000401";

export const m4FieldClass =
  "min-h-12 w-full rounded-[var(--radius-control)] border-border bg-card text-foreground placeholder:text-muted-foreground hover:border-foreground/40 user-invalid:border-destructive focus-visible:border-ring focus-visible:ring-ring/50 motion-reduce:transition-none";
export const m4TextAreaClass = `${m4FieldClass} min-h-28 resize-y py-3 font-mono text-sm`;
export const m4PrimaryButtonClass =
  "min-h-12 rounded-[var(--radius-control)] border-primary bg-primary px-4 font-semibold text-primary-foreground hover:bg-primary/90 motion-reduce:transition-none";
export const m4SecondaryButtonClass =
  "min-h-12 rounded-[var(--radius-control)] border-border bg-card px-4 font-semibold text-foreground hover:bg-accent hover:text-accent-foreground motion-reduce:transition-none";
export const m4DangerButtonClass =
  "min-h-12 rounded-[var(--radius-control)] border-destructive bg-destructive px-4 font-semibold text-destructive-foreground hover:bg-destructive/90 motion-reduce:transition-none";
export const m4LabelClass =
  "grid min-w-0 gap-2 text-xs font-bold tracking-[0.04em] text-muted-foreground uppercase";
export const m4SectionClass = "border-b border-[var(--line)] py-7 sm:py-9";

const previewWorkspaces: readonly M4WorkspaceOption[] = Object.freeze([
  Object.freeze({ id: M4_PREVIEW_WORKSPACE_ID, name: "Vynlo North" }),
  Object.freeze({
    id: "10000000-0000-4000-8000-000000000402",
    name: "Vynlo Service",
  }),
]);

interface WorkspaceMembershipRecord {
  readonly workspace_id?: unknown;
  readonly workspaces?: unknown;
}

function workspaceOptions(value: unknown): readonly M4WorkspaceOption[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const options: M4WorkspaceOption[] = [];
  for (const item of value) {
    if (typeof item !== "object" || item === null) continue;
    const membership = item as WorkspaceMembershipRecord;
    const relation = Array.isArray(membership.workspaces)
      ? membership.workspaces[0]
      : membership.workspaces;
    const workspace =
      typeof relation === "object" && relation !== null
        ? (relation as Readonly<Record<string, unknown>>)
        : null;
    const id = workspace?.id ?? membership.workspace_id;
    const name = workspace?.name;
    if (typeof id !== "string" || typeof name !== "string" || seen.has(id)) {
      continue;
    }
    seen.add(id);
    options.push(Object.freeze({ id, name }));
  }
  return Object.freeze(options);
}

export interface M4OperatorRuntimeState {
  readonly apiContext: M4ApiContext;
  readonly canWrite: boolean;
  readonly online: boolean;
  readonly previewMode: boolean;
  readonly selectedWorkspaceId: string;
}

export interface M4OperatorRuntimeProps {
  readonly attentionCount: number;
  readonly children: (runtime: M4OperatorRuntimeState) => ReactNode;
  readonly copy: M4Messages;
  readonly current: M4NavigationKey;
  readonly eyebrow: string;
  readonly jobState?: ReactNode;
  readonly locale: Locale;
  readonly previewMode: boolean;
  readonly saveState?: ReactNode;
  readonly summary: string;
  readonly title: string;
}

export function M4OperatorRuntime({
  attentionCount,
  children,
  copy,
  current,
  eyebrow,
  jobState,
  locale,
  previewMode,
  saveState,
  summary,
  title,
}: M4OperatorRuntimeProps) {
  const router = useRouter();
  const liveContextRequest = useRef(0);
  const [accessToken, setAccessToken] = useState<string | null>(
    previewMode ? "preview.header.signature" : null,
  );
  const [workspaces, setWorkspaces] = useState<readonly M4WorkspaceOption[]>(
    previewMode ? previewWorkspaces : [],
  );
  const [selectedWorkspaceId, setSelectedWorkspaceId] = useState(
    previewMode ? M4_PREVIEW_WORKSPACE_ID : "",
  );
  const [loading, setLoading] = useState(!previewMode);
  const [loadError, setLoadError] = useState(false);
  const online = useOperatorOnlineStatus();

  const loadLiveContext = useCallback(async () => {
    if (previewMode) return;
    const requestId = ++liveContextRequest.current;
    setLoading(true);
    setLoadError(false);
    try {
      const client = getBrowserSupabase();
      const session = (await client.auth.getSession()).data.session;
      if (!session) {
        if (liveContextRequest.current === requestId) router.replace("/login");
        return;
      }
      const membershipResult = await client
        .from("workspace_memberships")
        .select("workspace_id,workspaces!inner(id,name)")
        .eq("user_id", session.user.id)
        .eq("status", "active")
        .order("created_at", { ascending: true });
      if (membershipResult.error) throw membershipResult.error;
      const options = workspaceOptions(membershipResult.data);
      if (options.length === 0) throw new TypeError("workspace_required");
      if (liveContextRequest.current !== requestId) return;
      setAccessToken(session.access_token);
      setWorkspaces(options);
      setSelectedWorkspaceId((currentValue) =>
        options.some((option) => option.id === currentValue)
          ? currentValue
          : options[0]!.id,
      );
    } catch {
      if (liveContextRequest.current === requestId) setLoadError(true);
    } finally {
      if (liveContextRequest.current === requestId) setLoading(false);
    }
  }, [previewMode, router]);

  useEffect(() => {
    let active = true;
    queueMicrotask(() => {
      if (active) void loadLiveContext();
    });
    return () => {
      active = false;
      liveContextRequest.current += 1;
    };
  }, [loadLiveContext]);

  const runtime = useMemo<M4OperatorRuntimeState | null>(() => {
    if (!accessToken || !selectedWorkspaceId) return null;
    return Object.freeze({
      apiContext: Object.freeze({
        accessToken,
        workspaceId: selectedWorkspaceId,
      }),
      canWrite: online,
      online,
      previewMode,
      selectedWorkspaceId,
    });
  }, [accessToken, online, previewMode, selectedWorkspaceId]);

  return (
    <M4OperatorShell
      attentionCount={attentionCount}
      copy={copy.common}
      current={current}
      eyebrow={eyebrow}
      jobState={jobState}
      locale={locale}
      onWorkspaceChange={setSelectedWorkspaceId}
      online={online}
      previewMode={previewMode}
      saveState={saveState}
      selectedWorkspaceId={selectedWorkspaceId}
      summary={summary}
      title={title}
      workspaces={workspaces}
    >
      {!online ? (
        <div
          className="flex min-h-12 items-center gap-3 border-b border-[var(--line)] bg-[var(--ink)] px-4 text-sm font-semibold text-[var(--paper)] sm:px-6 lg:px-8"
          role="status"
        >
          <WifiOff aria-hidden="true" className="shrink-0" size={18} />
          {copy.common.offline}
        </div>
      ) : null}
      {loading ? (
        <div
          className="flex min-h-64 items-center justify-center gap-3 px-4 text-sm font-semibold text-muted-foreground"
          role="status"
        >
          <LoaderCircle
            aria-hidden="true"
            className="animate-spin motion-reduce:animate-none"
            size={20}
          />
          {copy.common.loading}
        </div>
      ) : null}
      {loadError ? (
        <section className="mx-auto grid max-w-2xl gap-4 px-4 py-16 sm:px-6">
          <AlertTriangle aria-hidden="true" size={28} />
          <h2 className="m-0 text-2xl">{copy.common.errorHeading}</h2>
          <p className="m-0 text-sm leading-6 text-muted-foreground">
            {copy.common.errorDescription}
          </p>
          <Button
            className={`${m4SecondaryButtonClass} justify-self-start`}
            onClick={() => void loadLiveContext()}
            type="button"
          >
            {copy.common.retry}
          </Button>
        </section>
      ) : null}
      {!loading && !loadError && runtime ? children(runtime) : null}
    </M4OperatorShell>
  );
}

export function M4InlineStatus({
  error,
  message,
}: {
  readonly error?: boolean;
  readonly message: string;
}) {
  return (
    <p
      aria-live="polite"
      className={`m-0 min-h-6 text-sm font-semibold ${
        error ? "text-[var(--rust)]" : "text-muted-foreground"
      }`}
      role={error ? "alert" : "status"}
    >
      {message}
    </p>
  );
}

export function M4StatusPill({
  label,
  status,
}: {
  readonly label: string;
  readonly status: string;
}) {
  const attention = [
    "dead_letter",
    "failed",
    "generation_failed",
    "rejected",
    "voided",
  ].includes(status);
  const complete = [
    "active",
    "approved",
    "completed",
    "generated",
    "succeeded",
  ].includes(status);
  return (
    <span
      className={`inline-flex min-h-7 items-center gap-2 rounded-full border px-2 font-mono text-[0.68rem] font-semibold tracking-[0.04em] uppercase ${
        attention
          ? "border-[var(--rust)] text-[var(--rust)]"
          : complete
            ? "border-success bg-success text-success-foreground"
            : "border-[var(--line)] text-muted-foreground"
      }`}
      data-status={status}
    >
      <span
        aria-hidden="true"
        className={`size-1.5 rounded-full ${
          attention
            ? "bg-[var(--rust)]"
            : complete
              ? "bg-success-foreground"
              : "bg-[var(--muted)]"
        }`}
      />
      {label}
    </span>
  );
}
