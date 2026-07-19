// Stable test IDs: T-DOC-001, T-DOC-002, T-DOC-003, T-DOC-004, T-DOC-005.
import { describe, expect, it } from "vitest";

import {
  resolveOfficialDocumentConfiguration,
  resolvePreviewDocumentConfiguration,
} from "./configuration";
import { DocumentDomainError } from "./domain-common";
import { PREVIEW_WATERMARK } from "./first-vertical-slice";
import {
  assertDocumentFileImmutable,
  assertDocumentImmutableFields,
  createOfficialDocument,
  createPreviewDocument,
  failDocumentRender,
  markDocumentSigned,
  recordGeneratedDocumentFile,
  registerSignedDocumentFile,
  retryDocumentRender,
  selectCurrentSignedFile,
  supersedeDocument,
  voidDocument,
} from "./lifecycle";
import {
  M4_TEST_IDS,
  makeM4ConfigurationFixture,
  PDF_CHECKSUM,
  renderInput,
} from "./m4-test-fixtures";

function officialConfiguration() {
  const fixture = makeM4ConfigurationFixture();
  return resolveOfficialDocumentConfiguration({
    ...fixture,
    now: "2026-07-16T12:00:00.000Z",
  });
}

function previewConfiguration() {
  const fixture = makeM4ConfigurationFixture({
    documentStatus: "reviewed",
    numberingStatus: "draft",
    productionApproved: false,
    productionEnabled: false,
    templateStatus: "reviewed",
  });
  return resolvePreviewDocumentConfiguration({
    documentType: fixture.documentType,
    template: fixture.template,
  });
}

function officialDocument(
  id: string = M4_TEST_IDS.document,
  name: string = "Alice",
  officialNumber: string = "INV-000001",
  allocationId: string = M4_TEST_IDS.allocation,
) {
  const input = renderInput(name);
  return createOfficialDocument({
    id,
    configuration: officialConfiguration(),
    renderInputSnapshot: input.snapshot,
    renderInputChecksum: input.checksum,
    officialNumber,
    numberAllocationId: allocationId,
    intendedSignatureDate: "2026-07-20",
  });
}

function generatedFile(
  id: string = M4_TEST_IDS.fileGenerated,
  storageFileId: string = M4_TEST_IDS.storageGenerated,
) {
  return {
    id,
    storageFileId,
    filename: "official.pdf",
    mimeType: "application/pdf",
    byteSize: 38,
    checksum: PDF_CHECKSUM,
    createdAt: "2026-07-16T12:05:00.000Z",
  };
}

function signedFile(input: {
  id: string;
  storageFileId: string;
  checksum: string;
}) {
  return {
    ...input,
    filename: "signed.pdf",
    mimeType: "application/pdf",
    byteSize: 42,
    createdAt: "2026-07-16T13:00:00.000Z",
  };
}

describe("T-DOC-001 preview invariants", () => {
  it("creates freely regenerable watermarked records without official numbers", () => {
    const input = renderInput("Alice");
    const first = createPreviewDocument({
      id: M4_TEST_IDS.document,
      configuration: previewConfiguration(),
      renderInputSnapshot: input.snapshot,
      renderInputChecksum: input.checksum,
    });
    const second = createPreviewDocument({
      id: M4_TEST_IDS.documentReplacement,
      configuration: previewConfiguration(),
      renderInputSnapshot: input.snapshot,
      renderInputChecksum: input.checksum,
    });
    expect(first).toMatchObject({
      mode: "preview",
      officialNumber: null,
      numberAllocationId: null,
      intendedSignatureDate: null,
      watermark: PREVIEW_WATERMARK,
      status: "queued",
    });
    expect(second.id).not.toBe(first.id);
    expect(second.renderInputChecksum).toBe(first.renderInputChecksum);
  });

  it("accepts only one immutable PDF artifact for a preview", () => {
    const input = renderInput("Alice");
    const preview = createPreviewDocument({
      id: M4_TEST_IDS.document,
      configuration: previewConfiguration(),
      renderInputSnapshot: input.snapshot,
      renderInputChecksum: input.checksum,
    });
    const generated = recordGeneratedDocumentFile({
      document: preview,
      file: { ...generatedFile(), filename: "preview.pdf" },
    });
    expect(generated).toMatchObject({
      status: "generated",
      generatedChecksum: PDF_CHECKSUM,
      files: [{ role: "preview", version: 1 }],
    });
    expect(
      recordGeneratedDocumentFile({
        document: generated,
        file: { ...generatedFile(), filename: "preview.pdf" },
      }),
    ).toBe(generated);
  });
});

describe("T-DOC-002 / T-DOC-003 official snapshot and render retry", () => {
  it("pins the number, allocation, input, and every exact configuration version", () => {
    const document = officialDocument();
    expect(document).toMatchObject({
      mode: "official",
      status: "queued",
      officialNumber: "INV-000001",
      numberAllocationId: M4_TEST_IDS.allocation,
      watermark: null,
      renderAttempt: 1,
      version: 1,
    });
    expect(document.documentType.checksum).toHaveLength(64);
    expect(document.template.sourceBundleChecksum).toHaveLength(64);
    expect(document.numbering.checksum).toHaveLength(64);
    expect(Object.isFrozen(document.renderInputSnapshot)).toBe(true);
    expect(Object.isFrozen(document.renderInputSnapshot.customer)).toBe(true);
  });

  it("retries a failed render without changing or reallocating official data", () => {
    const original = officialDocument();
    const failed = failDocumentRender({
      document: original,
      failureCode: "pdf.chromium_timeout",
    });
    const retried = retryDocumentRender(failed);
    expect(retried).toMatchObject({
      status: "queued",
      failureCode: null,
      renderAttempt: 2,
      officialNumber: original.officialNumber,
      numberAllocationId: original.numberAllocationId,
      renderInputChecksum: original.renderInputChecksum,
    });
    expect(() =>
      assertDocumentImmutableFields({ previous: original, next: retried }),
    ).not.toThrow();

    const generated = recordGeneratedDocumentFile({
      document: retried,
      file: generatedFile(),
    });
    expect(generated.files).toEqual([
      expect.objectContaining({ role: "generated_original", version: 1 }),
    ]);
    expect(
      recordGeneratedDocumentFile({
        document: generated,
        file: generatedFile(),
      }),
    ).toBe(generated);
    expect(() =>
      recordGeneratedDocumentFile({
        document: generated,
        file: {
          ...generatedFile(
            "17000000-0000-4000-8000-000000000099",
            "18000000-0000-4000-8000-000000000099",
          ),
          checksum: "f".repeat(64),
        },
      }),
    ).toThrowError(
      expect.objectContaining({ code: "duplicate_document_file" }),
    );
  });

  it("rejects malformed numbers, allocation IDs, snapshots, and transition replay", () => {
    const input = renderInput("Alice");
    expect(() =>
      createOfficialDocument({
        id: M4_TEST_IDS.document,
        configuration: officialConfiguration(),
        renderInputSnapshot: input.snapshot,
        renderInputChecksum: "f".repeat(64),
        officialNumber: "../../etc/passwd",
        numberAllocationId: "not-a-uuid",
        intendedSignatureDate: "2026-02-31",
      }),
    ).toThrowError(DocumentDomainError);
    expect(() => retryDocumentRender(officialDocument())).toThrowError(
      expect.objectContaining({ code: "invalid_document_transition" }),
    );
  });
});

describe("T-DOC-004 / T-DOC-005 signed, void, and supersession lineage", () => {
  it("appends signed versions and changes only the current-selection pointer", () => {
    const generated = recordGeneratedDocumentFile({
      document: officialDocument(),
      file: generatedFile(),
    });
    const first = registerSignedDocumentFile({
      document: generated,
      file: signedFile({
        id: M4_TEST_IDS.fileSignedOne,
        storageFileId: M4_TEST_IDS.storageSignedOne,
        checksum: "a".repeat(64),
      }),
    });
    const second = registerSignedDocumentFile({
      document: first,
      file: signedFile({
        id: M4_TEST_IDS.fileSignedTwo,
        storageFileId: M4_TEST_IDS.storageSignedTwo,
        checksum: "b".repeat(64),
      }),
    });
    expect(
      registerSignedDocumentFile({
        document: second,
        file: signedFile({
          id: M4_TEST_IDS.fileSignedTwo,
          storageFileId: M4_TEST_IDS.storageSignedTwo,
          checksum: "b".repeat(64),
        }),
      }),
    ).toBe(second);
    expect(second.files.filter((file) => file.role === "signed_scan")).toEqual([
      expect.objectContaining({ id: M4_TEST_IDS.fileSignedOne, version: 1 }),
      expect.objectContaining({ id: M4_TEST_IDS.fileSignedTwo, version: 2 }),
    ]);
    expect(second.currentSignedFileId).toBe(M4_TEST_IDS.fileSignedTwo);
    const reselected = selectCurrentSignedFile({
      document: second,
      fileId: M4_TEST_IDS.fileSignedOne,
    });
    expect(reselected.currentSignedFileId).toBe(M4_TEST_IDS.fileSignedOne);
    const signed = markDocumentSigned(reselected);
    expect(signed.status).toBe("signed");
    expect(() =>
      assertDocumentFileImmutable({
        previous: second.files[1]!,
        next: { ...second.files[1]!, checksum: "c".repeat(64) },
      }),
    ).toThrowError(
      expect.objectContaining({ code: "immutable_document_field" }),
    );
  });

  it("requires stronger authorization to void a signed document and preserves files", () => {
    const withFile = registerSignedDocumentFile({
      document: recordGeneratedDocumentFile({
        document: officialDocument(),
        file: generatedFile(),
      }),
      file: signedFile({
        id: M4_TEST_IDS.fileSignedOne,
        storageFileId: M4_TEST_IDS.storageSignedOne,
        checksum: "a".repeat(64),
      }),
    });
    const signed = markDocumentSigned(withFile);
    expect(() =>
      voidDocument({
        document: signed,
        reason: "Customer rescinded",
        allowSignedVoid: false,
      }),
    ).toThrowError(
      expect.objectContaining({ code: "invalid_document_transition" }),
    );
    const voided = voidDocument({
      document: signed,
      reason: "Customer rescinded",
      allowSignedVoid: true,
    });
    expect(voided).toMatchObject({
      status: "voided",
      voidReason: "Customer rescinded",
      officialNumber: "INV-000001",
    });
    expect(voided.files).toBe(signed.files);
    expect(
      voidDocument({
        document: voided,
        reason: "Customer rescinded",
        allowSignedVoid: true,
      }),
    ).toBe(voided);
  });

  it("voids an unrecoverable official render without erasing its failure or number", () => {
    const failed = failDocumentRender({
      document: officialDocument(),
      failureCode: "renderer.permanent_failure",
    });
    const voided = voidDocument({
      document: failed,
      reason: "Abandon failed replacement and issue a fresh successor",
      allowSignedVoid: false,
    });

    expect(voided).toMatchObject({
      status: "voided",
      failureCode: "renderer.permanent_failure",
      officialNumber: "INV-000001",
      numberAllocationId: M4_TEST_IDS.allocation,
      voidReason: "Abandon failed replacement and issue a fresh successor",
    });
    expect(() => retryDocumentRender(voided)).toThrowError(
      expect.objectContaining({ code: "invalid_document_transition" }),
    );
    expect(() =>
      voidDocument({
        document: { ...voided, failureCode: null },
        reason: "Abandon failed replacement and issue a fresh successor",
        allowSignedVoid: false,
      }),
    ).toThrowError(expect.objectContaining({ code: "invalid_document" }));
    expect(() =>
      voidDocument({
        document: officialDocument(),
        reason: "Cannot abandon an active render",
        allowSignedVoid: false,
      }),
    ).toThrowError(
      expect.objectContaining({ code: "invalid_document_transition" }),
    );
  });

  it("links a changed snapshot to a fresh number while preserving the original", () => {
    const original = recordGeneratedDocumentFile({
      document: officialDocument(),
      file: generatedFile(),
    });
    const replacement = officialDocument(
      M4_TEST_IDS.documentReplacement,
      "Alice Corrected",
      "INV-000002",
      M4_TEST_IDS.allocationReplacement,
    );
    const result = supersedeDocument({
      original,
      replacement,
      reason: "Corrected legal name",
    });
    expect(result.original).toMatchObject({
      status: "superseded",
      supersededByDocumentId: replacement.id,
      officialNumber: "INV-000001",
      files: original.files,
    });
    expect(result.replacement).toMatchObject({
      status: "queued",
      supersedesDocumentId: original.id,
      supersedesReason: "Corrected legal name",
      officialNumber: "INV-000002",
      files: [],
    });
    expect(original.status).toBe("generated");
    expect(original.supersededByDocumentId).toBeNull();
  });

  it("rejects supersession that reuses input, number, allocation, or lineage", () => {
    const original = officialDocument();
    const unchanged = renderInput("Alice");
    const sameInput = createOfficialDocument({
      id: M4_TEST_IDS.documentReplacement,
      configuration: officialConfiguration(),
      renderInputSnapshot: unchanged.snapshot,
      renderInputChecksum: unchanged.checksum,
      officialNumber: "INV-000001",
      numberAllocationId: M4_TEST_IDS.allocation,
      intendedSignatureDate: "2026-07-20",
    });
    expect(() =>
      supersedeDocument({
        original,
        replacement: sameInput,
        reason: "No change",
      }),
    ).toThrowError(
      expect.objectContaining({ code: "invalid_document_transition" }),
    );
  });
});
