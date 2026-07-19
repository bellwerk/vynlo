// Stable test IDs: T-UX-002.
import { describe, expect, it } from "vitest";
import { foundationTokens } from "./index";

describe("foundation design tokens", () => {
  it("keeps the minimum touch target at 44 CSS pixels", () => {
    expect(foundationTokens.touchTarget).toBe("var(--touch-target)");
  });

  it("exposes semantic references without duplicating runtime values", () => {
    expect(foundationTokens.color.signal).toBe("var(--primary)");
    expect(foundationTokens.focus.width).toBe("var(--focus-width)");
    expect(Object.isFrozen(foundationTokens)).toBe(true);
    expect(Object.isFrozen(foundationTokens.color)).toBe(true);
  });
});
