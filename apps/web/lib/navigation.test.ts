import type { PlatformPermissionKey } from "@vynlo/auth";
import { describe, expect, it } from "vitest";
import { applicationNavigation, filterNavigation } from "./navigation";

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
});
