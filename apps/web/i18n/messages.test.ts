import { describe, expect, it } from "vitest";
import { messages } from "./messages";

describe("foundation message catalogs", () => {
  it("keeps English and French top-level keys aligned", () => {
    expect(Object.keys(messages.fr)).toEqual(Object.keys(messages.en));
  });

  it("preserves French accents", () => {
    expect(messages.fr.heading).toContain("équipes");
  });
});
