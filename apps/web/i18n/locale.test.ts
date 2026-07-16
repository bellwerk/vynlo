// Stable test IDs: T-I18N-001.
import { describe, expect, it } from "vitest";
import { isSupportedLocale, resolveLocale, sanitizeReturnPath } from "./locale";

describe("locale policy", () => {
  it("accepts only supported machine-stable locale keys", () => {
    expect(isSupportedLocale("en")).toBe(true);
    expect(isSupportedLocale("fr")).toBe(true);
    expect(isSupportedLocale("fr-CA")).toBe(false);
    expect(resolveLocale("unknown")).toBe("en");
  });

  it("keeps locale redirects inside the application", () => {
    expect(sanitizeReturnPath("/health?source=shell")).toBe(
      "/health?source=shell",
    );
    expect(sanitizeReturnPath("https://example.invalid")).toBe("/");
    expect(sanitizeReturnPath("//example.invalid")).toBe("/");
    expect(sanitizeReturnPath("/\\example.invalid")).toBe("/");
    expect(sanitizeReturnPath(null)).toBe("/");
  });
});
