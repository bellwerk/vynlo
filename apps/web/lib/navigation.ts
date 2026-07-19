import type { PlatformPermissionKey } from "@vynlo/auth";

export type NavigationKey =
  "overview" | "inventory" | "people" | "deals" | "system";

export type OperatorNavigationKey =
  | "inventory"
  | "people"
  | "deals"
  | "documents"
  | "configuration"
  | "exports"
  | "system";

export type MobileNavigationPlacement = "primary" | "more";
export type OperatorNavigationIconKey = OperatorNavigationKey;

export interface NavigationItem {
  readonly href: string;
  readonly key: NavigationKey;
  readonly permission?: PlatformPermissionKey;
}

export interface OperatorNavigationItem {
  readonly href: string;
  readonly icon: OperatorNavigationIconKey;
  readonly key: OperatorNavigationKey;
  readonly mobilePriority: number;
  readonly mobilePlacement: MobileNavigationPlacement;
  readonly permission?: PlatformPermissionKey;
  readonly translationKey: OperatorNavigationKey;
}

export const applicationNavigation = Object.freeze([
  { href: "/", key: "overview" },
  { href: "/inventory", key: "inventory", permission: "inventory.read" },
  { href: "/people", key: "people", permission: "crm.read" },
  { href: "/deals", key: "deals", permission: "deals.read" },
  { href: "/health", key: "system" },
] as const satisfies readonly NavigationItem[]);

/**
 * One tenant-neutral navigation contract for every authenticated workbench.
 * API authorization remains authoritative; this model controls discoverability
 * only and always uses immutable permission keys rather than role labels.
 */
export const operatorNavigation = Object.freeze([
  {
    href: "/inventory",
    icon: "inventory",
    key: "inventory",
    mobilePriority: 1,
    mobilePlacement: "primary",
    permission: "inventory.read",
    translationKey: "inventory",
  },
  {
    href: "/people",
    icon: "people",
    key: "people",
    mobilePriority: 2,
    mobilePlacement: "primary",
    permission: "crm.read",
    translationKey: "people",
  },
  {
    href: "/deals",
    icon: "deals",
    key: "deals",
    mobilePriority: 3,
    mobilePlacement: "primary",
    permission: "deals.read",
    translationKey: "deals",
  },
  {
    href: "/documents",
    icon: "documents",
    key: "documents",
    mobilePriority: 4,
    mobilePlacement: "primary",
    permission: "documents.read",
    translationKey: "documents",
  },
  {
    href: "/configuration",
    icon: "configuration",
    key: "configuration",
    mobilePriority: 5,
    mobilePlacement: "more",
    permission: "configuration.read",
    translationKey: "configuration",
  },
  {
    href: "/exports",
    icon: "exports",
    key: "exports",
    mobilePriority: 6,
    mobilePlacement: "more",
    permission: "exports.read",
    translationKey: "exports",
  },
  {
    href: "/health",
    icon: "system",
    key: "system",
    mobilePriority: 7,
    mobilePlacement: "more",
    translationKey: "system",
  },
] as const satisfies readonly OperatorNavigationItem[]);

export function filterNavigation<
  TItem extends Readonly<{ href: string; key: string }>,
>(
  items: readonly TItem[],
  grantedPermissions: ReadonlySet<PlatformPermissionKey>,
): readonly TItem[] {
  return items.filter((item) => {
    const permission =
      "permission" in item
        ? (item.permission as PlatformPermissionKey | undefined)
        : undefined;
    return permission === undefined || grantedPermissions.has(permission);
  });
}
