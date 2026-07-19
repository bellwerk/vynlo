import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

function source(file: string): string {
  return readFileSync(join(process.cwd(), "apps/web/components", file), "utf8");
}

describe("T-DOC-001..006 / T-NUM-001..003 M4 operator controls", () => {
  it("separates validation, unnumbered preview, and explicit official allocation", () => {
    const documentSource = source("m4-document-workbench.tsx");
    expect(documentSource).toContain('path: "/api/v1/documents/validate"');
    expect(documentSource).toContain('"/api/v1/documents/preview"');
    expect(documentSource).toContain('"/api/v1/documents/official"');
    expect(documentSource).toContain("allocationConfirmed");
    expect(documentSource).toContain("validation?.official_ready !== true");
    expect(documentSource).toContain("officialKey.current");
  });

  it("keeps immutable file, retry, signed, void, and supersession actions visible", () => {
    const documentSource = source("m4-document-workbench.tsx");
    for (const action of [
      "retry-render",
      "mark-signed",
      'mutate("void"',
      "/supersede",
      "/files/",
    ]) {
      expect(documentSource).toContain(action);
    }
    expect(documentSource).toContain("LegalOriginalUpload");
    expect(documentSource).toContain("version_snapshot");
    expect(documentSource).toContain(
      "/api/v1/document-preview-artifacts/${encodeURIComponent(artifactId)}/download-grants",
    );
    expect(documentSource).toContain("m4DocumentActionEligibility(document)");
    expect(
      documentSource.match(/expectedVersion: document\.aggregate_version/gu),
    ).toHaveLength(2);
  });
});

describe("T-CALC-001..002 / T-TAX-001..002 / T-EXP-001..002", () => {
  it("exposes checksum-bound lifecycle and append-only approval forms", () => {
    const configurationSource = source("m4-configuration-workbench.tsx");
    expect(configurationSource).toContain("expectedChecksum");
    expect(configurationSource).toContain("expectedVersion");
    expect(configurationSource).toContain('path: "/api/v1/approval-records"');
    expect(configurationSource).toContain("professionalOrganization");
    expect(configurationSource).toContain("official_document_created");
    expect(configurationSource).toContain(
      "dealId: runtimeDealId.trim() || null",
    );
    expect(configurationSource).toContain('"vehicle_price_minor"');
    expect(configurationSource).not.toContain("useState('{\"passed\":true}')");
  });

  it("keeps every report phone-readable before a deterministic export", () => {
    const exportSource = source("m4-exports-workbench.tsx");
    for (const report of [
      "inventory-aging",
      "inventory-gross",
      "leads",
      "deals",
    ]) {
      expect(exportSource).toContain(report);
    }
    expect(exportSource).toContain('role="tablist"');
    expect(exportSource).toContain("formatM3MinorAmount");
    expect(exportSource).toContain("/download");
  });
});

describe("T-UX-001 / T-UX-002 accessibility contract", () => {
  it("ships skip navigation, persistent live status, reduced motion, and 44px controls", () => {
    const shellSource = source("m4-operator-shell.tsx");
    const sharedShellSource = source("operator-shell.tsx");
    const runtimeSource = source("m4-operator-runtime.tsx");
    expect(shellSource).toContain('mainId="m4-main"');
    expect(shellSource).toContain("<OperatorShell");
    expect(sharedShellSource).toContain("href={`#${mainId}`}");
    expect(sharedShellSource).toContain('aria-current={active ? "page"');
    expect(runtimeSource).toContain('aria-live="polite"');
    expect(runtimeSource).toContain("min-h-12");
    expect(runtimeSource).toContain("motion-reduce:transition-none");
  });

  it("remounts every workspace-owned workbench when workspace context changes", () => {
    for (const file of [
      "m4-document-workbench.tsx",
      "m4-configuration-workbench.tsx",
      "m4-exports-workbench.tsx",
    ]) {
      expect(source(file)).toContain("key={runtime.selectedWorkspaceId}");
    }
  });

  it("styles the official render failure state as requiring attention", () => {
    expect(source("m4-operator-runtime.tsx")).toContain('"generation_failed"');
  });
});
