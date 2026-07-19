// Stable test IDs: T-RBAC-001, T-UX-001.
import type { PlatformPermissionKey } from "@vynlo/auth";
import { describe, expect, it } from "vitest";
import {
  applicationNavigation,
  filterNavigation,
  operatorNavigation,
} from "./navigation";

describe("permission-aware navigation", () => {
  it("keeps public destinations and hides unauthorized modules", () => {
    expect(
      filterNavigation(applicationNavigation, new Set()).map(({ key }) => key),
    ).toEqual(["overview", "system"]);
  });

  it("reveals only modules represented by immutable permission keys", () => {
    const grants = new Set<PlatformPermissionKey>([
      "inventory.read",
      "deals.read",
    ]);

    expect(
      filterNavigation(applicationNavigation, grants).map(({ key }) => key),
    ).toEqual(["overview", "inventory", "deals", "system"]);
  });

  it("keeps four primary mobile destinations and moves utilities into More", () => {
    const grants = new Set<PlatformPermissionKey>([
      "configuration.read",
      "crm.read",
      "deals.read",
      "documents.read",
      "exports.read",
      "inventory.read",
    ]);
    const visible = filterNavigation(operatorNavigation, grants);

    expect(
      visible
        .filter(({ mobilePlacement }) => mobilePlacement === "primary")
        .map(({ key }) => key),
    ).toEqual(["inventory", "people", "deals", "documents"]);
    expect(
      visible
        .filter(({ mobilePlacement }) => mobilePlacement === "more")
        .map(({ key }) => key),
    ).toEqual(["configuration", "exports", "system"]);
  });

  it("carries one typed route, translation, icon, permission, and priority contract", () => {
    expect(
      operatorNavigation.map((item) => ({
        href: item.href,
        icon: item.icon,
        key: item.key,
        mobilePriority: item.mobilePriority,
        permission: "permission" in item ? item.permission : null,
        translationKey: item.translationKey,
      })),
    ).toEqual([
      {
        href: "/inventory",
        icon: "inventory",
        key: "inventory",
        mobilePriority: 1,
        permission: "inventory.read",
        translationKey: "inventory",
      },
      {
        href: "/people",
        icon: "people",
        key: "people",
        mobilePriority: 2,
        permission: "crm.read",
        translationKey: "people",
      },
      {
        href: "/deals",
        icon: "deals",
        key: "deals",
        mobilePriority: 3,
        permission: "deals.read",
        translationKey: "deals",
      },
      {
        href: "/documents",
        icon: "documents",
        key: "documents",
        mobilePriority: 4,
        permission: "documents.read",
        translationKey: "documents",
      },
      {
        href: "/configuration",
        icon: "configuration",
        key: "configuration",
        mobilePriority: 5,
        permission: "configuration.read",
        translationKey: "configuration",
      },
      {
        href: "/exports",
        icon: "exports",
        key: "exports",
        mobilePriority: 6,
        permission: "exports.read",
        translationKey: "exports",
      },
      {
        href: "/health",
        icon: "system",
        key: "system",
        mobilePriority: 7,
        permission: null,
        translationKey: "system",
      },
    ]);
  });
});
