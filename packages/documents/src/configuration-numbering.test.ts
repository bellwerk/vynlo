// Stable test IDs: T-DOC-002, T-DOC-006, T-NUM-001, T-NUM-002, T-NUM-003.
import { describe, expect, it } from "vitest";

import {
  normalizeDocumentTemplateVersion,
  normalizeDocumentTypeVersion,
  resolveOfficialDocumentConfiguration,
  resolvePreviewDocumentConfiguration,
} from "./configuration";
import { DocumentDomainError, sha256Hex } from "./domain-common";
import { officialDocumentPdfFilename } from "./artifact-filename";
import { makeM4ConfigurationFixture } from "./m4-test-fixtures";
import {
  assertNumberAllocationImmutable,
  computeNumberingDefinitionChecksum,
  formatDocumentNumber,
  normalizeNumberingDefinition,
  numberingPeriodKey,
  type NumberingDefinitionPayload,
} from "./numbering";

describe("T-DOC-002 / T-DOC-006 exact document configuration activation", () => {
  it("validates canonical SHA-256 and exact version/checksum bindings", () => {
    expect(sha256Hex("abc")).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
    const fixture = makeM4ConfigurationFixture();
    expect(normalizeDocumentTypeVersion(fixture.documentType)).toEqual(
      fixture.documentType,
    );
    expect(normalizeDocumentTemplateVersion(fixture.template)).toEqual(
      fixture.template,
    );
    const resolved = resolveOfficialDocumentConfiguration({
      ...fixture,
      now: "2026-07-16T12:00:00.000Z",
    });
    expect(resolved).toMatchObject({
      productionReady: true,
      documentType: { checksum: fixture.documentType.checksum },
      template: {
        checksum: fixture.template.checksum,
        sourceBundleChecksum: fixture.template.sourceBundle.checksum,
      },
      numbering: { checksum: fixture.numbering.checksum },
      fieldSchemaChecksum: fixture.documentType.fieldSchemaChecksum,
    });
    expect(resolved.activationEvidence).toHaveLength(3);
  });

  it("allows reviewed exact candidates for preview without making them production-ready", () => {
    const fixture = makeM4ConfigurationFixture({
      documentStatus: "reviewed",
      numberingStatus: "draft",
      productionApproved: false,
      productionEnabled: false,
      templateStatus: "reviewed",
    });
    expect(
      resolvePreviewDocumentConfiguration({
        documentType: fixture.documentType,
        template: fixture.template,
      }),
    ).toMatchObject({ productionReady: false, activationEvidence: [] });
    expect(() =>
      resolveOfficialDocumentConfiguration({
        ...fixture,
        now: "2026-07-16T12:00:00.000Z",
      }),
    ).toThrowError(expect.objectContaining({ code: "invalid_activation" }));
  });

  it("rejects payload mutation, unknown fields, and schema/source checksum drift", () => {
    const fixture = makeM4ConfigurationFixture();
    expect(() =>
      normalizeDocumentTypeVersion({
        ...fixture.documentType,
        labels: { en: "Changed", fr: "Modifié" },
      }),
    ).toThrowError(expect.objectContaining({ code: "checksum_mismatch" }));
    expect(() =>
      normalizeDocumentTemplateVersion({
        ...fixture.template,
        sourceBundle: {
          ...fixture.template.sourceBundle,
          sourceHtml: "<p>Changed</p>",
        },
      }),
    ).toThrowError(expect.objectContaining({ code: "checksum_mismatch" }));
    expect(() =>
      normalizeDocumentTypeVersion({
        ...fixture.documentType,
        javascript: "x",
      }),
    ).toThrowError(DocumentDomainError);
  });

  const invalidApprovalCases: Array<
    [
      string,
      (
        fixture: ReturnType<typeof makeM4ConfigurationFixture>,
      ) => readonly unknown[],
    ]
  > = [
    [
      "missing",
      (fixture: ReturnType<typeof makeM4ConfigurationFixture>) =>
        fixture.approvals.slice(1),
    ],
    [
      "expired",
      (fixture: ReturnType<typeof makeM4ConfigurationFixture>) =>
        fixture.approvals.map((approval, index) =>
          index === 0
            ? { ...approval, expiresAt: "2026-07-15T12:00:00.000Z" }
            : approval,
        ),
    ],
    [
      "wrong checksum",
      (fixture: ReturnType<typeof makeM4ConfigurationFixture>) =>
        fixture.approvals.map((approval, index) =>
          index === 0
            ? { ...approval, artifactChecksum: "f".repeat(64) }
            : approval,
        ),
    ],
    [
      "revoked",
      (fixture: ReturnType<typeof makeM4ConfigurationFixture>) =>
        fixture.approvals.map((approval, index) =>
          index === 0
            ? { ...approval, decision: "revoked" as const }
            : approval,
        ),
    ],
  ];

  it.each(invalidApprovalCases)(
    "rejects %s exact-version approval evidence",
    (_label, mutate) => {
      const fixture = makeM4ConfigurationFixture();
      expect(() =>
        resolveOfficialDocumentConfiguration({
          ...fixture,
          approvals: mutate(fixture),
          now: "2026-07-16T12:00:00.000Z",
        }),
      ).toThrowError(expect.objectContaining({ code: "approval_required" }));
    },
  );

  it("uses the latest append-only approval decision without falling back", () => {
    const fixture = makeM4ConfigurationFixture();
    const original = fixture.approvals[0]!;
    expect(() =>
      resolveOfficialDocumentConfiguration({
        ...fixture,
        approvals: [
          ...fixture.approvals,
          {
            ...original,
            id: "15000000-0000-4000-8000-000000000099",
            decision: "revoked",
            decidedAt: "2026-07-16T11:00:00.000Z",
            expiresAt: null,
          },
        ],
        now: "2026-07-16T12:00:00.000Z",
      }),
    ).toThrowError(expect.objectContaining({ code: "approval_required" }));
  });

  it("requires approved/active, production-enabled definitions with exact parity", () => {
    for (const fixture of [
      makeM4ConfigurationFixture({ documentStatus: "reviewed" }),
      makeM4ConfigurationFixture({ templateStatus: "retired" }),
      makeM4ConfigurationFixture({ numberingStatus: "draft" }),
      makeM4ConfigurationFixture({ productionEnabled: false }),
      makeM4ConfigurationFixture({ productionApproved: false }),
    ]) {
      expect(() =>
        resolveOfficialDocumentConfiguration({
          ...fixture,
          now: "2026-07-16T12:00:00.000Z",
        }),
      ).toThrowError(expect.objectContaining({ code: "invalid_activation" }));
    }
  });
});

function periodicDefinition(input: {
  reset: "yearly" | "monthly";
  deterministicSuffix?: "none" | "provided";
}) {
  const fixture = makeM4ConfigurationFixture();
  const { checksum: _checksum, status: _status, ...base } = fixture.numbering;
  void _checksum;
  void _status;
  const suffixMode = input.deterministicSuffix ?? "none";
  const payload: NumberingDefinitionPayload = {
    ...base,
    reset: input.reset,
    formatPattern:
      "{{prefix}}{{scope}}-{{period}}-{{sequence:6}}" +
      (suffixMode === "provided" ? "-{{deterministic_suffix}}" : ""),
    deterministicSuffix: suffixMode,
  };
  return {
    ...payload,
    checksum: computeNumberingDefinitionChecksum(payload),
    status: "active" as const,
  };
}

describe("T-NUM-001 / T-NUM-002 / T-NUM-003 generic document numbering", () => {
  it("derives bounded portable filenames without changing the legal number", () => {
    expect(officialDocumentPdfFilename("INV-2026-000001")).toBe(
      "INV-2026-000001.pdf",
    );
    expect(officialDocumentPdfFilename("CON")).toMatch(
      /^CON-[a-f0-9]{16}\.pdf$/u,
    );
    expect(officialDocumentPdfFilename("A/B")).not.toBe(
      officialDocumentPdfFilename("A\\B"),
    );
    expect(officialDocumentPdfFilename("LEGAL/2026/échange")).toBe(
      "LEGAL-2026-change-4e8ca26ffeeec1ee.pdf",
    );
    expect(officialDocumentPdfFilename("x".repeat(128))).toHaveLength(132);
    expect(() => officialDocumentPdfFilename("x".repeat(129))).toThrow(
      TypeError,
    );
    expect(officialDocumentPdfFilename("\u{1f697}".repeat(128))).toMatch(
      /^document-[a-f0-9]{16}\.pdf$/u,
    );
    expect(() => officialDocumentPdfFilename("\u{1f697}".repeat(129))).toThrow(
      TypeError,
    );
    expect(officialDocumentPdfFilename("\u00a0LEGAL\u00a0")).toMatch(
      /^LEGAL-[a-f0-9]{16}\.pdf$/u,
    );
  });

  it("formats 100 unique monotonically ordered values under one immutable definition", () => {
    const definition = normalizeNumberingDefinition(
      makeM4ConfigurationFixture().numbering,
    );
    const numbers = Array.from({ length: 100 }, (_, index) =>
      formatDocumentNumber({
        definition,
        sequenceValue: String(index + 1),
        scopeKey: "retail.sale",
        periodKey: "never",
      }),
    );
    expect(new Set(numbers).size).toBe(100);
    expect(numbers[0]).toBe("INV-retail.sale-000001");
    expect(numbers[99]).toBe("INV-retail.sale-000100");
    expect([...numbers].sort()).toEqual(numbers);
  });

  it("uses the configured timezone for yearly and monthly period keys", () => {
    expect(
      numberingPeriodKey({
        instant: "2026-01-01T04:30:00.000Z",
        reset: "yearly",
        timezone: "America/Toronto",
      }),
    ).toBe("2025");
    expect(
      numberingPeriodKey({
        instant: "2026-03-01T04:30:00.000Z",
        reset: "monthly",
        timezone: "America/Toronto",
      }),
    ).toBe("2026-02");
    const definition = normalizeNumberingDefinition(
      periodicDefinition({ reset: "monthly", deterministicSuffix: "provided" }),
    );
    expect(
      formatDocumentNumber({
        definition,
        sequenceValue: "7",
        scopeKey: "retail.sale",
        periodKey: "2026-02",
        deterministicSuffix: "A_1",
      }),
    ).toBe("INV-retail.sale-2026-02-000007-A_1");
  });

  it("is a pure proposal formatter, so abandoned validation creates no allocation state", () => {
    const definition = makeM4ConfigurationFixture().numbering;
    const before = structuredClone(definition);
    expect(
      formatDocumentNumber({
        definition,
        sequenceValue: definition.startingValue,
        scopeKey: "retail.sale",
        periodKey: "never",
      }),
    ).toBe("INV-retail.sale-000001");
    expect(definition).toEqual(before);
  });

  it("rejects arbitrary format code, mismatched period/suffix, overflow, and checksum drift", () => {
    const fixture = makeM4ConfigurationFixture();
    const invalidPatterns = [
      "{{prefix}}{{eval:6}}",
      "{{prefix}}{{sequence:5}}",
      "{{prefix}}{{sequence:6}}{{sequence:6}}",
      "{{prefix}} {{sequence:6}}",
    ];
    for (const formatPattern of invalidPatterns) {
      const {
        checksum: _checksum,
        status: _status,
        ...base
      } = fixture.numbering;
      void _checksum;
      void _status;
      const payload = { ...base, formatPattern };
      expect(() =>
        normalizeNumberingDefinition({
          ...payload,
          checksum: computeNumberingDefinitionChecksum(payload),
          status: "draft",
        }),
      ).toThrowError(DocumentDomainError);
    }
    expect(() =>
      formatDocumentNumber({
        definition: fixture.numbering,
        sequenceValue: "1000000",
        scopeKey: "retail.sale",
        periodKey: "never",
      }),
    ).toThrowError(expect.objectContaining({ code: "number_out_of_range" }));
    expect(() =>
      normalizeNumberingDefinition({
        ...fixture.numbering,
        increment: "2",
      }),
    ).toThrowError(expect.objectContaining({ code: "checksum_mismatch" }));
  });

  it("prohibits reuse by rejecting any change to a committed allocation", () => {
    const allocation = {
      definitionId: "13000000-0000-4000-8000-000000000001",
      sequenceValue: "1",
      formattedValue: "INV-000001",
      documentId: "16000000-0000-4000-8000-000000000001",
    };
    expect(() =>
      assertNumberAllocationImmutable({
        previous: allocation,
        next: allocation,
      }),
    ).not.toThrow();
    expect(() =>
      assertNumberAllocationImmutable({
        previous: allocation,
        next: {
          ...allocation,
          documentId: "16000000-0000-4000-8000-000000000002",
        },
      }),
    ).toThrowError(
      expect.objectContaining({ code: "immutable_document_field" }),
    );
  });
});
