import { describe, expect, it } from "vitest";

import { m4Messages } from "./m4-messages";

function shape(value: unknown): unknown {
  if (typeof value === "function") return "function";
  if (typeof value !== "object" || value === null) return typeof value;
  return Object.fromEntries(
    Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, entry]) => [key, shape(entry)]),
  );
}

function strings(value: unknown): readonly string[] {
  if (typeof value === "string") return [value];
  if (typeof value !== "object" || value === null) return [];
  return Object.values(value).flatMap(strings);
}

describe("T-I18N-001 / M4-EXIT-AC-001 operator catalogues", () => {
  it("keeps the complete English and French catalogue shapes aligned", () => {
    expect(shape(m4Messages.fr)).toEqual(shape(m4Messages.en));
    for (const locale of ["en", "fr"] as const) {
      expect(strings(m4Messages[locale]).every((entry) => entry.trim())).toBe(
        true,
      );
    }
  });

  it("states irreversible numbering and preview behavior in both languages", () => {
    expect(m4Messages.en.documents.confirmAllocationHint).toContain(
      "never reused",
    );
    expect(m4Messages.en.documents.previewNumberPolicy).toContain(
      "No official",
    );
    expect(m4Messages.fr.documents.confirmAllocationHint).toContain("jamais");
    expect(m4Messages.fr.documents.previewNumberPolicy).toContain(
      "Aucun numéro",
    );
  });

  it("localizes every durable document, job, and configuration status", () => {
    for (const locale of ["en", "fr"] as const) {
      expect(Object.keys(m4Messages[locale].documents.statuses)).toEqual([
        "completed",
        "failed",
        "generation_failed",
        "generated",
        "generating",
        "queued",
        "signed_received",
        "superseded",
        "voided",
      ]);
      expect(Object.keys(m4Messages[locale].documents.fileRoles)).toEqual([
        "attachment",
        "generated_original",
        "preview",
        "signed_scan",
        "void_notice",
      ]);
      expect(Object.keys(m4Messages[locale].configuration.statuses)).toEqual([
        "active",
        "approved",
        "draft",
        "retired",
        "test_passed",
        "validated",
      ]);
    }
  });
});
