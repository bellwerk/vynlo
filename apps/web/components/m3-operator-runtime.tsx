/* Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4
 * Hallmark · genre: modern-minimal · macrostructure: Workbench
 * tone: utilitarian-austere · palette: inherited Vynlo · enrichment: none
 */
"use client";

import { Button } from "@vynlo/ui-web";
import { AlertTriangle, LoaderCircle, WifiOff } from "lucide-react";
import { useRouter } from "next/navigation";
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
import type { M3Messages } from "../i18n/m3-messages";
import type { M3ApiContext } from "../lib/m3-api-client";
import { getBrowserSupabase } from "../lib/supabase-browser";
import {
  M3OperatorShell,
  type M3NavigationKey,
  type M3WorkspaceOption,
} from "./m3-operator-shell";

export const M3_PREVIEW_WORKSPACE_ID = "10000000-0000-4000-8000-000000000301";
export const M3_PREVIEW_SECONDARY_WORKSPACE_ID =
  "10000000-0000-4000-8000-000000000302";

const previewWorkspaces: readonly M3WorkspaceOption[] = Object.freeze([
  Object.freeze({ id: M3_PREVIEW_WORKSPACE_ID, name: "Vynlo North" }),
  Object.freeze({
    id: M3_PREVIEW_SECONDARY_WORKSPACE_ID,
    name: "Vynlo Service",
  }),
]);

export const m3FieldClass =
  "min-h-12 w-full rounded-[var(--radius-control)] border-border bg-card text-foreground placeholder:text-muted-foreground hover:border-foreground/40 user-invalid:border-destructive focus-visible:border-ring focus-visible:ring-ring/50 motion-reduce:transition-none";
export const m3TextAreaClass = `${m3FieldClass} min-h-28 resize-y py-3`;
export const m3PrimaryButtonClass =
  "min-h-12 rounded-[var(--radius-control)] border-primary bg-primary px-4 font-semibold text-primary-foreground hover:bg-primary/90 motion-reduce:transition-none";
export const m3SecondaryButtonClass =
  "min-h-12 rounded-[var(--radius-control)] border-border bg-card px-4 font-semibold text-foreground hover:bg-accent hover:text-accent-foreground motion-reduce:transition-none";
export const m3LinkButtonClass =
  "inline-flex min-h-11 items-center justify-center gap-2 whitespace-nowrap rounded-[var(--radius-control)] border border-border bg-card px-3 text-sm font-semibold text-foreground no-underline hover:bg-accent hover:text-accent-foreground";

interface WorkspaceMembershipRecord {
  readonly workspace_id?: unknown;
  readonly workspaces?: unknown;
}

function workspaceOptions(value: unknown): readonly M3WorkspaceOption[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const options: M3WorkspaceOption[] = [];
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

export interface M3OperatorRuntimeState {
  readonly apiContext: M3ApiContext;
  readonly canWrite: boolean;
  readonly online: boolean;
  readonly previewMode: boolean;
  readonly selectedWorkspaceId: string;
}

export interface M3OperatorRuntimeProps {
  readonly attentionCount: number;
  readonly children: (runtime: M3OperatorRuntimeState) => ReactNode;
  readonly copy: M3Messages;
  readonly current: M3NavigationKey;
  readonly eyebrow: string;
  readonly jobState?: ReactNode;
  readonly locale: Locale;
  readonly previewMode: boolean;
  readonly saveState?: ReactNode;
  readonly summary: string;
  readonly title: string;
}

export function M3OperatorRuntime({
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
}: M3OperatorRuntimeProps) {
  const router = useRouter();
  const liveContextRequest = useRef(0);
  const [accessToken, setAccessToken] = useState<string | null>(
    previewMode ? "preview.header.signature" : null,
  );
  const [workspaces, setWorkspaces] = useState<readonly M3WorkspaceOption[]>(
    previewMode ? previewWorkspaces : [],
  );
  const [selectedWorkspaceId, setSelectedWorkspaceId] = useState(
    previewMode ? M3_PREVIEW_WORKSPACE_ID : "",
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

  const runtime = useMemo<M3OperatorRuntimeState | null>(() => {
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
    <M3OperatorShell
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
          <p className="m-0 max-w-[60ch] text-sm leading-6 text-muted-foreground">
            {copy.common.errorDescription}
          </p>
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start`}
            onClick={() => void loadLiveContext()}
            type="button"
          >
            {copy.common.retry}
          </Button>
        </section>
      ) : null}

      {!loading && !loadError && runtime ? children(runtime) : null}
    </M3OperatorShell>
  );
}

export function M3InlineStatus({
  copy,
  error,
  saved,
  saving,
}: {
  readonly copy: M3Messages["common"];
  readonly error: string | null;
  readonly saved: boolean;
  readonly saving: boolean;
}) {
  const message = error ?? (saving ? copy.saving : saved ? copy.saved : "");
  return (
    <p
      aria-live="polite"
      className={`m-0 min-h-6 text-sm font-semibold ${
        error ? "text-[var(--rust)]" : "text-muted-foreground"
      }`}
      data-state={
        error ? "error" : saving ? "saving" : saved ? "saved" : "idle"
      }
    >
      {message}
    </p>
  );
}
