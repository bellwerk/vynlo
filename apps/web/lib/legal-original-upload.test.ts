import { describe, expect, it } from "vitest";

import {
  legalOriginalSha256Hex,
  legalOriginalReceiptStatus,
  legalOriginalStorageUrl,
  legalOriginalStatusMessageKey,
  legalOriginalStatusShouldPoll,
  MAX_LEGAL_ORIGINAL_BYTES,
  parseLegalOriginalUploadIntent,
  parseLegalOriginalVerificationReceipt,
  parseLegalOriginalVerificationStatus,
  validateLegalOriginalFile,
} from "./legal-original-upload";

const documentId = "15000000-0000-4000-8000-000000000011";
const sessionId = "15000000-0000-4000-8000-000000000012";

function intent() {
  return parseLegalOriginalUploadIntent({
    data: {
      documentId,
      expiresAt: "2026-07-16T18:00:00.000Z",
      mediaKind: "legal_document",
      upload: {
        bucket: "media-private",
        objectKey: "workspaces/one/documents/original #1.pdf",
      },
      uploadSessionId: sessionId,
    },
  });
}

describe("T-MED-002 / T-MED-003 legal original browser upload contract", () => {
  it("accepts the exact PDF and image policy and infers empty browser MIME", () => {
    for (const type of [
      "application/pdf",
      "image/jpeg",
      "image/png",
      "image/webp",
      "image/heic",
      "image/heif",
    ]) {
      expect(
        validateLegalOriginalFile({ name: "original.bin", size: 1, type }),
      ).toMatchObject({ mimeType: type, valid: true });
    }
    expect(
      validateLegalOriginalFile({ name: "signed.PDF", size: 1, type: "" }),
    ).toEqual({ mimeType: "application/pdf", valid: true });
  });

  it("fails closed for empty, oversized, and unsupported files", () => {
    expect(
      validateLegalOriginalFile({ name: "empty.pdf", size: 0, type: "" }),
    ).toEqual({ code: "file_empty", valid: false });
    expect(
      validateLegalOriginalFile({
        name: "large.pdf",
        size: MAX_LEGAL_ORIGINAL_BYTES + 1,
        type: "application/pdf",
      }),
    ).toEqual({ code: "file_too_large", valid: false });
    expect(
      validateLegalOriginalFile({
        name: "notes.txt",
        size: 1,
        type: "text/plain",
      }),
    ).toEqual({ code: "unsupported_file_type", valid: false });
  });

  it("hashes the original bytes and parses exact command receipts", async () => {
    await expect(legalOriginalSha256Hex(new Blob(["vynlo"]))).resolves.toBe(
      "d28b7da36626cba66ee087d8b41da1243c137e342aaacafa9232b338dbf00922",
    );
    expect(intent()).toMatchObject({ documentId, uploadSessionId: sessionId });
    expect(
      parseLegalOriginalVerificationReceipt({
        data: {
          documentId,
          job: {
            id: "15000000-0000-4000-8000-000000000013",
            status: "queued",
          },
          uploadSessionId: sessionId,
        },
      }),
    ).toMatchObject({ documentId, jobStatus: "queued" });
  });

  it("encodes each provider-key segment and rejects traversal", () => {
    expect(
      legalOriginalStorageUrl("https://example.supabase.co/", intent()),
    ).toBe(
      "https://example.supabase.co/storage/v1/object/media-private/workspaces/one/documents/original%20%231.pdf",
    );
    expect(() =>
      legalOriginalStorageUrl("https://example.supabase.co", {
        ...intent(),
        upload: { bucket: "media-private", objectKey: "workspaces/../secret" },
      }),
    ).toThrow("invalid_legal_original_object_key");
  });

  it("parses safe projected status but discards raw failure codes", () => {
    const projected = parseLegalOriginalVerificationStatus({
      data: {
        completedAt: null,
        documentId,
        failure: {
          classification: "transient",
          code: "media.private_worker_failure_code",
        },
        job: {
          attemptCount: 6,
          id: "15000000-0000-4000-8000-000000000013",
          maximumAttempts: 6,
          retryAt: null,
        },
        mediaKind: "legal_document",
        retryable: true,
        status: "dead_letter",
        uploadSessionId: sessionId,
      },
    });
    expect(projected).toMatchObject({
      retryable: true,
      status: "dead_letter",
    });
    expect(JSON.stringify(projected)).not.toContain(
      "media.private_worker_failure_code",
    );
    expect(legalOriginalStatusMessageKey(projected.status)).toBe(
      "statusDeadLetter",
    );
    expect(legalOriginalStatusShouldPoll(projected.status)).toBe(false);
  });

  it("requires explicit status job/failure shapes and maps only translated states", () => {
    const base = {
      completedAt: null,
      documentId,
      mediaKind: "legal_document",
      retryable: false,
      uploadSessionId: sessionId,
    } as const;
    expect(() =>
      parseLegalOriginalVerificationStatus({
        data: { ...base, status: "running" },
      }),
    ).toThrow("invalid_legal_original_status_response");
    expect(() =>
      parseLegalOriginalVerificationStatus({
        data: {
          ...base,
          failure: null,
          job: {
            attemptCount: 6,
            id: "15000000-0000-4000-8000-000000000013",
            maximumAttempts: 6,
            retryAt: null,
          },
          retryable: true,
          status: "dead_letter",
        },
      }),
    ).toThrow("invalid_legal_original_status_response");
    expect(
      legalOriginalStatusMessageKey(legalOriginalReceiptStatus("retry_wait")),
    ).toBe("statusRetryWait");
    expect(legalOriginalStatusShouldPoll("running")).toBe(true);
    expect(legalOriginalStatusMessageKey("rejected")).toBe("statusRejected");
    expect(legalOriginalStatusMessageKey("completed")).toBe("statusCompleted");
  });

  it("rejects malformed provider envelopes", () => {
    expect(() =>
      parseLegalOriginalUploadIntent({
        data: {
          documentId,
          expiresAt: "invalid",
          mediaKind: "legal_document",
          upload: { bucket: "public", objectKey: "bad" },
          uploadSessionId: sessionId,
        },
      }),
    ).toThrow("invalid_legal_original_intent_response");
    expect(() =>
      parseLegalOriginalVerificationReceipt({
        data: {
          documentId,
          job: { id: documentId, status: "invented" },
          uploadSessionId: sessionId,
        },
      }),
    ).toThrow("invalid_legal_original_verification_response");
  });
});
