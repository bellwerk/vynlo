import { describe, expect, it } from "vitest";
import { messages } from "./messages";

function catalogShape(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(catalogShape);
  }

  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, child]) => [key, catalogShape(child)]),
    );
  }

  return typeof value;
}

describe("message catalogs", () => {
  it("keeps the complete English and French catalog structures aligned", () => {
    expect(catalogShape(messages.fr)).toEqual(catalogShape(messages.en));
  });

  it("preserves French accents and language-independent machine keys", () => {
    expect(messages.fr.heading).toContain("préparation");
    expect(Object.keys(messages.fr.navigation)).toEqual(
      Object.keys(messages.en.navigation),
    );
  });
});
