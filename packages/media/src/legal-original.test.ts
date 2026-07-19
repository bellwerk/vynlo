import { describe, expect, it } from "vitest";

import { MediaPolicyError } from "./errors";
import {
  buildLegalOriginalQuarantineCleanupJobPayload,
  parseLegalOriginalQuarantineCleanupJob,
} from "./job-contract";
import {
  buildLegalOriginalVerificationReceipt,
  detectLegalOriginalMimeType,
  normalizeLegalOriginalIntent,
  parseLegalOriginalVerificationReceipt,
} from "./legal-original";

const ids = {
  job: "b9000000-0000-4000-8000-000000000001",
  lease: "b9000000-0000-4000-8000-000000000002",
  session: "b9000000-0000-4000-8000-000000000003",
  workspace: "b9000000-0000-4000-8000-000000000004",
} as const;
const checksum = "a".repeat(64);

describe("T-MED-002 / T-MED-003 preserved legal original policy", () => {
  it("normalizes a bounded immutable PDF intent and rejects oversized bytes", () => {
    expect(
      normalizeLegalOriginalIntent({
        byteSize: 50_000_000,
        checksumSha256: checksum,
        filename: " registration.pdf ",
        mediaKind: "legal_document",
        mimeType: "APPLICATION/PDF",
      }),
    ).toEqual(
      expect.objectContaining({
        byteSize: 50_000_000,
        filename: "registration.pdf",
        mimeType: "application/pdf",
      }),
    );
    expect(() =>
      normalizeLegalOriginalIntent({
        byteSize: 50_000_001,
        checksumSha256: checksum,
        filename: "registration.pdf",
        mediaKind: "legal_document",
        mimeType: "application/pdf",
      }),
    ).toThrow(new MediaPolicyError("invalid_legal_original"));
  });

  it("detects PDF and supported image signatures without changing bytes", () => {
    expect(
      detectLegalOriginalMimeType(
        new TextEncoder().encode("%PDF-1.7\nsynthetic fixture"),
      ),
    ).toBe("application/pdf");
    expect(
      detectLegalOriginalMimeType(
        Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      ),
    ).toBe("image/png");
    expect(detectLegalOriginalMimeType(new Uint8Array([1, 2, 3]))).toBeNull();
  });

  it("builds a strict deeply immutable receipt and rejects extra keys", () => {
    const receipt = buildLegalOriginalVerificationReceipt({
      attempt: 1,
      bucket: "media-private",
      byteSize: 1_000,
      checksumSha256: checksum,
      generation: "etag-1",
      jobId: ids.job,
      leaseId: ids.lease,
      malwareScan: {
        scanner: { name: "clamd", version: "1.4.2" },
        signatureVersion: "27345",
        sourceChecksumSha256: checksum,
        verdict: "clean",
      },
      mimeType: "application/pdf",
      objectKey:
        "workspaces/example/documents/example/upload-intents/example/source",
      workerId: "legal-worker-1",
    });
    expect(parseLegalOriginalVerificationReceipt(receipt)).toEqual(receipt);
    expect(Object.isFrozen(receipt.storage)).toBe(true);
    expect(() =>
      parseLegalOriginalVerificationReceipt({ ...receipt, untrusted: true }),
    ).toThrow(new MediaPolicyError("invalid_legal_original_receipt"));
  });

  it("parses only the exact legal quarantine cleanup job envelope", () => {
    const payload = buildLegalOriginalQuarantineCleanupJobPayload({
      reason: "terminal_rejection",
      uploadSessionId: ids.session,
    });
    expect(
      parseLegalOriginalQuarantineCleanupJob({
        entityId: ids.session,
        entityType: "legal_original_upload_session",
        jobType: "media.delete_legal_original_quarantine",
        payload,
        payloadSchemaVersion: 1,
        workspaceId: ids.workspace,
      }),
    ).toEqual({
      reason: "terminal_rejection",
      uploadSessionId: ids.session,
      workspaceId: ids.workspace,
    });
    expect(() =>
      parseLegalOriginalQuarantineCleanupJob({
        entityId: ids.session,
        entityType: "legal_original_upload_session",
        jobType: "media.delete_legal_original_quarantine",
        payload: { ...payload, storageKey: "secret" },
        payloadSchemaVersion: 1,
        workspaceId: ids.workspace,
      }),
    ).toThrow(new MediaPolicyError("invalid_job_contract"));
  });
});
