import type { PlatformPermissionKey } from "@vynlo/auth";

export type NavigationKey =
  "overview" | "inventory" | "people" | "deals" | "system";

export interface NavigationItem {
  readonly href: string;
  readonly key: NavigationKey;
  readonly permission?: PlatformPermissionKey;
}

export const applicationNavigation = Object.freeze([
  { href: "/", key: "overview" },
  { href: "/inventory", key: "inventory", permission: "inventory.read" },
  { href: "/people", key: "people", permission: "crm.read" },
  { href: "/deals", key: "deals", permission: "deals.read" },
  { href: "/health", key: "system" },
] as const satisfies readonly NavigationItem[]);

export function filterNavigation(
  items: readonly NavigationItem[],
  grantedPermissions: ReadonlySet<PlatformPermissionKey>,
): readonly NavigationItem[] {
  return items.filter(
    (item) =>
      item.permission === undefined || grantedPermissions.has(item.permission),
  );
}
