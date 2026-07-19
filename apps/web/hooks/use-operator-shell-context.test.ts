// Stable test IDs: UI-MIG-04, T-RBAC-001, T-UX-001.
import { describe, expect, it } from "vitest";

import {
  OPERATOR_HEADER_STATUS_COPY,
  OPERATOR_PREVIEW_PERMISSION_KEYS,
  operatorNavigationHref,
  operatorPermissionKeysFromRows,
  resolveOperatorAccountContext,
  resolveOperatorOnlineStatus,
  resolveOperatorShellPermissions,
  safeOperatorSearchParameters,
} from "./use-operator-shell-context";

describe("operator shell context", () => {
  it("reports only truthful account and connectivity states in both locales", () => {
    expect(resolveOperatorAccountContext("m3", false)).toBe("preview");
    expect(resolveOperatorAccountContext(null, undefined)).toBe("checking");
    expect(resolveOperatorAccountContext(null, true)).toBe("authenticated");
    expect(resolveOperatorAccountContext(null, false)).toBe("signed-out");
    expect(resolveOperatorOnlineStatus(undefined, false)).toBe(false);
    expect(resolveOperatorOnlineStatus(true, false)).toBe(true);

    expect(OPERATOR_HEADER_STATUS_COPY.en).toMatchObject({
      authenticated: "Authenticated",
      offline: "Offline",
      preview: "Preview data",
    });
    expect(OPERATOR_HEADER_STATUS_COPY.fr).toMatchObject({
      authenticated: "Authentifi\u00e9",
      offline: "Hors ligne",
      preview: "Donn\u00e9es d\u2019aper\u00e7u",
    });
  });

  it("grants preview fixtures every permission declared by operator navigation", () => {
    expect(OPERATOR_PREVIEW_PERMISSION_KEYS).toEqual([
      "inventory.read",
      "crm.read",
      "deals.read",
      "documents.read",
      "configuration.read",
      "exports.read",
    ]);
  });

  it("accepts only immutable platform permission keys from live rows", () => {
    expect([
      ...operatorPermissionKeysFromRows([
        { key: "inventory.read" },
        { key: "crm.read" },
        { key: "workspace-owner" },
        { key: null },
      ]),
    ]).toEqual(["inventory.read", "crm.read"]);
  });

  it("prefers explicit grants and hides stale live-workspace grants", () => {
    const explicit = new Set(["deals.read"] as const);
    const live = new Set(["inventory.read"] as const);

    expect(
      resolveOperatorShellPermissions({
        explicitPermissions: explicit,
        livePermissions: live,
        liveWorkspaceId: "workspace-a",
        previewMode: "m3",
        selectedWorkspaceId: "workspace-b",
      }),
    ).toBe(explicit);
    expect([
      ...(resolveOperatorShellPermissions({
        explicitPermissions: undefined,
        livePermissions: undefined,
        liveWorkspaceId: undefined,
        previewMode: "m4",
        selectedWorkspaceId: "preview-workspace",
      }) ?? []),
    ]).toEqual(OPERATOR_PREVIEW_PERMISSION_KEYS);
    expect(
      resolveOperatorShellPermissions({
        explicitPermissions: undefined,
        livePermissions: live,
        liveWorkspaceId: "workspace-a",
        previewMode: null,
        selectedWorkspaceId: "workspace-b",
      }),
    ).toBeUndefined();
    expect(
      resolveOperatorShellPermissions({
        explicitPermissions: undefined,
        livePermissions: live,
        liveWorkspaceId: "workspace-b",
        previewMode: null,
        selectedWorkspaceId: "workspace-b",
      }),
    ).toBe(live);
  });

  it("preserves only the declared safe query allowlist", () => {
    const safe = safeOperatorSearchParameters(
      new URLSearchParams(
        "direction=desc&page=2&preview=m3&q=lee&q=li&sort=name&status=open&tab=timeline&view=table&workspace=ws-1&token=secret&returnTo=%2Fadmin",
      ),
    );

    expect(safe.toString()).toBe(
      "direction=desc&page=2&preview=m3&q=lee&q=li&sort=name&status=open&tab=timeline&view=table&workspace=ws-1",
    );
  });

  it("transforms preview for the target module and drops unsafe context", () => {
    const href = operatorNavigationHref({
      href: "/documents?token=base-secret",
      key: "documents",
      previewMode: "m3",
      searchParameters: new URLSearchParams(
        "preview=m3&workspace=ws-1&tab=timeline&token=current-secret",
      ),
    });

    expect(href).toBe("/documents?preview=m4&tab=timeline&workspace=ws-1");
  });

  it("drops preview context for live and public-system destinations", () => {
    const source = new URLSearchParams(
      "preview=m4&workspace=ws-1&status=failed&unsafe=yes",
    );

    expect(
      operatorNavigationHref({
        href: "/inventory",
        key: "inventory",
        previewMode: null,
        searchParameters: source,
      }),
    ).toBe("/inventory?status=failed&workspace=ws-1");
    expect(
      operatorNavigationHref({
        href: "/health",
        key: "system",
        previewMode: "m4",
        searchParameters: source,
      }),
    ).toBe("/health?status=failed&workspace=ws-1");
  });
});
