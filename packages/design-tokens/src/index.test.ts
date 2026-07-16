// Stable test IDs: T-UX-002.
import { describe, expect, it } from "vitest";
import { foundationTokens } from "./index";

describe("foundation design tokens", () => {
  it("keeps the minimum touch target at 44 CSS pixels", () => {
    expect(foundationTokens.touchTarget).toBe("44px");
  });

  it("exposes one primary signal color and stable focus geometry", () => {
    expect(foundationTokens.color.signal).toBe("#d9ff5b");
    expect(foundationTokens.focus.width).toBe("3px");
    expect(Object.isFrozen(foundationTokens)).toBe(true);
  });
});
