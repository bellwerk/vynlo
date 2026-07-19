"use client";

import {
  isPlatformPermissionKey,
  type PlatformPermissionKey,
} from "@vynlo/auth";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";

import {
  operatorNavigation,
  type OperatorNavigationKey,
} from "../lib/navigation";
import { getBrowserSupabase } from "../lib/supabase-browser";

export type OperatorPreviewMode = "inventory" | "m3" | "m4" | null;
export type OperatorAccountContext =
  "authenticated" | "checking" | "preview" | "signed-out";

export const OPERATOR_SAFE_QUERY_KEYS = Object.freeze([
  "direction",
  "page",
  "preview",
  "q",
  "sort",
  "status",
  "tab",
  "view",
  "workspace",
] as const);

export const OPERATOR_HEADER_STATUS_COPY = {
  en: {
    account: "Account",
    authenticated: "Authenticated",
    checking: "Checking access",
    connectivity: "Connectivity",
    group: "Account, connectivity, and job status",
    offline: "Offline",
    online: "Online",
    preview: "Preview data",
    signedOut: "Sign-in required",
  },
  fr: {
    account: "Compte",
    authenticated: "Authentifi\u00e9",
    checking: "V\u00e9rification de l\u2019acc\u00e8s",
    connectivity: "Connectivit\u00e9",
    group: "\u00c9tat du compte, de la connexion et des t\u00e2ches",
    offline: "Hors ligne",
    online: "En ligne",
    preview: "Donn\u00e9es d\u2019aper\u00e7u",
    signedOut: "Connexion requise",
  },
} as const;

export const OPERATOR_PREVIEW_PERMISSION_KEYS: readonly PlatformPermissionKey[] =
  Object.freeze(
    operatorNavigation.flatMap((item) =>
      "permission" in item && item.permission ? [item.permission] : [],
    ),
  );

const previewPermissions: ReadonlySet<PlatformPermissionKey> = new Set(
  OPERATOR_PREVIEW_PERMISSION_KEYS,
);

interface SearchParameterReader {
  getAll(name: string): readonly string[];
}

interface LoadedPermissions {
  readonly permissions: ReadonlySet<PlatformPermissionKey>;
  readonly workspaceId: string;
}

function subscribeToOnlineStatus(onStoreChange: () => void) {
  window.addEventListener("online", onStoreChange);
  window.addEventListener("offline", onStoreChange);
  return () => {
    window.removeEventListener("online", onStoreChange);
    window.removeEventListener("offline", onStoreChange);
  };
}

function browserOnlineSnapshot() {
  return navigator.onLine;
}

function serverOnlineSnapshot() {
  return true;
}

function records(value: unknown): readonly Readonly<Record<string, unknown>>[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) =>
    typeof item === "object" && item !== null && !Array.isArray(item)
      ? [item as Readonly<Record<string, unknown>>]
      : [],
  );
}

function stringValues(value: unknown, key: string): readonly string[] {
  return records(value).flatMap((item) =>
    typeof item[key] === "string" ? [item[key]] : [],
  );
}

export function operatorPermissionKeysFromRows(
  value: unknown,
): ReadonlySet<PlatformPermissionKey> {
  return new Set(
    records(value).flatMap((item) => {
      const key = item.key;
      return isPlatformPermissionKey(key) ? [key] : [];
    }),
  );
}

export function resolveOperatorShellPermissions({
  explicitPermissions,
  livePermissions,
  liveWorkspaceId,
  previewMode,
  selectedWorkspaceId,
}: {
  readonly explicitPermissions: ReadonlySet<PlatformPermissionKey> | undefined;
  readonly livePermissions: ReadonlySet<PlatformPermissionKey> | undefined;
  readonly liveWorkspaceId: string | undefined;
  readonly previewMode: OperatorPreviewMode;
  readonly selectedWorkspaceId: string;
}): ReadonlySet<PlatformPermissionKey> | undefined {
  if (explicitPermissions !== undefined) return explicitPermissions;
  if (previewMode !== null) return previewPermissions;
  return liveWorkspaceId === selectedWorkspaceId ? livePermissions : undefined;
}

export function resolveOperatorAccountContext(
  previewMode: OperatorPreviewMode,
  authenticated: boolean | undefined,
): OperatorAccountContext {
  if (previewMode !== null) return "preview";
  if (authenticated === undefined) return "checking";
  return authenticated ? "authenticated" : "signed-out";
}

export function resolveOperatorOnlineStatus(
  explicitOnline: boolean | undefined,
  browserOnline: boolean,
): boolean {
  return explicitOnline ?? browserOnline;
}

export function safeOperatorSearchParameters(
  source: SearchParameterReader,
): URLSearchParams {
  const safe = new URLSearchParams();
  for (const key of OPERATOR_SAFE_QUERY_KEYS) {
    for (const value of source.getAll(key)) safe.append(key, value);
  }
  return safe;
}

function targetPreview(
  key: OperatorNavigationKey,
): Exclude<OperatorPreviewMode, null> | null {
  if (key === "inventory") return "inventory";
  if (key === "people" || key === "deals") return "m3";
  if (key === "documents" || key === "configuration" || key === "exports") {
    return "m4";
  }
  return null;
}

export function operatorNavigationHref({
  href,
  key,
  previewMode,
  searchParameters,
}: {
  readonly href: string;
  readonly key: OperatorNavigationKey;
  readonly previewMode: OperatorPreviewMode;
  readonly searchParameters: SearchParameterReader;
}): string {
  const target = new URL(href, "https://vynlo.invalid");
  const safe = safeOperatorSearchParameters(target.searchParams);
  const current = safeOperatorSearchParameters(searchParameters);
  for (const key of OPERATOR_SAFE_QUERY_KEYS) {
    for (const value of current.getAll(key)) safe.append(key, value);
  }

  const transformedPreview = previewMode ? targetPreview(key) : null;
  if (transformedPreview) safe.set("preview", transformedPreview);
  else safe.delete("preview");

  const query = safeOperatorSearchParameters(safe).toString();
  return `${target.pathname}${query ? `?${query}` : ""}${target.hash}`;
}

async function loadActiveMembershipPermissions(
  workspaceId: string,
): Promise<ReadonlySet<PlatformPermissionKey>> {
  const client = getBrowserSupabase();
  const session = (await client.auth.getSession()).data.session;
  if (!session) return new Set();

  const membershipResult = await client
    .from("workspace_memberships")
    .select("id")
    .eq("user_id", session.user.id)
    .eq("workspace_id", workspaceId)
    .eq("status", "active")
    .limit(1);
  if (membershipResult.error) return new Set();
  const membershipId = stringValues(membershipResult.data, "id")[0];
  if (!membershipId) return new Set();

  const roleResult = await client
    .from("membership_roles")
    .select("role_id")
    .eq("workspace_id", workspaceId)
    .eq("membership_id", membershipId)
    .eq("status", "active");
  if (roleResult.error) return new Set();
  const roleIds = stringValues(roleResult.data, "role_id");
  if (roleIds.length === 0) return new Set();

  const activeRoleResult = await client
    .from("roles")
    .select("id")
    .eq("workspace_id", workspaceId)
    .eq("status", "active")
    .in("id", roleIds);
  if (activeRoleResult.error) return new Set();
  const activeRoleIds = stringValues(activeRoleResult.data, "id");
  if (activeRoleIds.length === 0) return new Set();

  const grantResult = await client
    .from("role_permissions")
    .select("permission_id")
    .eq("workspace_id", workspaceId)
    .eq("status", "active")
    .in("role_id", activeRoleIds);
  if (grantResult.error) return new Set();
  const permissionIds = stringValues(grantResult.data, "permission_id");
  if (permissionIds.length === 0) return new Set();

  const permissionResult = await client
    .from("permissions")
    .select("key")
    .eq("status", "active")
    .in("id", permissionIds);
  return permissionResult.error
    ? new Set()
    : operatorPermissionKeysFromRows(permissionResult.data);
}

/**
 * Resolves navigation-only grants without weakening route/API authorization.
 * Explicit grants win, preview fixtures receive every declared module grant,
 * and live grants are accepted only from the authenticated active membership.
 */
export function useOperatorShellPermissions({
  explicitPermissions,
  previewMode,
  selectedWorkspaceId,
}: {
  readonly explicitPermissions: ReadonlySet<PlatformPermissionKey> | undefined;
  readonly previewMode: OperatorPreviewMode;
  readonly selectedWorkspaceId: string;
}): ReadonlySet<PlatformPermissionKey> | undefined {
  const requestSequence = useRef(0);
  const [loaded, setLoaded] = useState<LoadedPermissions | null>(null);

  useEffect(() => {
    const requestId = ++requestSequence.current;
    let active = true;

    if (
      explicitPermissions !== undefined ||
      previewMode !== null ||
      !selectedWorkspaceId
    ) {
      return () => {
        active = false;
        if (requestSequence.current === requestId) requestSequence.current += 1;
      };
    }

    void loadActiveMembershipPermissions(selectedWorkspaceId)
      .catch(() => new Set<PlatformPermissionKey>())
      .then((permissions) => {
        if (active && requestSequence.current === requestId) {
          setLoaded({ permissions, workspaceId: selectedWorkspaceId });
        }
      });

    return () => {
      active = false;
      if (requestSequence.current === requestId) requestSequence.current += 1;
    };
  }, [explicitPermissions, previewMode, selectedWorkspaceId]);

  return resolveOperatorShellPermissions({
    explicitPermissions,
    livePermissions: loaded?.permissions,
    liveWorkspaceId: loaded?.workspaceId,
    previewMode,
    selectedWorkspaceId,
  });
}

export function useOperatorAccountContext(
  previewMode: OperatorPreviewMode,
): OperatorAccountContext {
  const requestSequence = useRef(0);
  const [authenticated, setAuthenticated] = useState<boolean | undefined>();

  useEffect(() => {
    const requestId = ++requestSequence.current;
    let active = true;
    let unsubscribe: (() => void) | undefined;

    if (previewMode !== null) {
      return () => {
        active = false;
        if (requestSequence.current === requestId) requestSequence.current += 1;
      };
    }

    try {
      const client = getBrowserSupabase();
      void client.auth
        .getSession()
        .then(({ data }) => {
          if (active && requestSequence.current === requestId) {
            setAuthenticated(data.session !== null);
          }
        })
        .catch(() => undefined);
      const authSubscription = client.auth.onAuthStateChange(
        (_event, session) => {
          if (active && requestSequence.current === requestId) {
            setAuthenticated(session !== null);
          }
        },
      );
      unsubscribe = () => authSubscription.data.subscription.unsubscribe();
    } catch {
      queueMicrotask(() => {
        if (active && requestSequence.current === requestId) {
          setAuthenticated(false);
        }
      });
    }

    return () => {
      active = false;
      unsubscribe?.();
      if (requestSequence.current === requestId) requestSequence.current += 1;
    };
  }, [previewMode]);

  return resolveOperatorAccountContext(previewMode, authenticated);
}

export function useOperatorOnlineStatus(explicitOnline?: boolean): boolean {
  const browserOnline = useSyncExternalStore(
    subscribeToOnlineStatus,
    browserOnlineSnapshot,
    serverOnlineSnapshot,
  );
  return resolveOperatorOnlineStatus(explicitOnline, browserOnline);
}
