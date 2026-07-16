import {
  buildLegalOriginalUploadVerificationJobPayload,
  type LegalOriginalObjectStorage,
  type MediaMalwareScanner,
} from "@vynlo/media";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { ClaimedJob } from "./job-store";
import { JobExecutionError } from "./job-runner";
import {
  createLegalOriginalUploadVerificationJobHandler,
  type LegalOriginalUploadVerificationRepository,
} from "./legal-original-upload-verification-handler";
import { mediaSha256Hex } from "./managed-media-storage";

const ids = {
  correlation: "b9000000-0000-4000-8000-000000000006",
  document: "b9000000-0000-4000-8000-000000000002",
  file: "b9000000-0000-4000-8000-000000000008",
  job: "b9000000-0000-4000-8000-000000000004",
  lease: "b9000000-0000-4000-8000-000000000005",
  media: "b9000000-0000-4000-8000-000000000009",
  session: "b9000000-0000-4000-8000-000000000007",
  user: "b9000000-0000-4000-8000-000000000010",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;

describe("T-MED-002 / T-MED-003 legal original upload verification worker", () => {
  let bytes: Uint8Array;
  let checksum: string;
  let job: ClaimedJob;

  beforeEach(async () => {
    bytes = new Uint8Array(1_000);
    bytes.set(new TextEncoder().encode("%PDF-1.7\nsynthetic fixture"));
    checksum = await mediaSha256Hex(bytes);
    job = {
      attemptNumber: 1,
      causationId: null,
      correlationId: ids.correlation,
      entityId: ids.document,
      entityType: "document",
      idempotencyKey: `media:verify-legal:${ids.session}`,
      jobId: ids.job,
      jobType: "media.verify_legal_original",
      leaseExpiresAt: "2099-01-01T00:00:00.000Z",
      leaseToken: ids.lease,
      maximumAttempts: 6,
      outboxEventId: "b9000000-0000-4000-8000-000000000011",
      payload: {
        ...buildLegalOriginalUploadVerificationJobPayload({
          uploadSessionId: ids.session,
        }),
      },
      payloadSchemaVersion: 1,
      workspaceId: ids.workspace,
    };
  });

  function storage(): LegalOriginalObjectStorage {
    return {
      readLegalOriginal: vi.fn().mockResolvedValue({
        generation: "etag-1",
        providerMimeType: "application/pdf",
        source: bytes,
      }),
    };
  }

  function repository() {
    const complete = vi
      .fn<LegalOriginalUploadVerificationRepository["complete"]>()
      .mockResolvedValue({
        mediaFileId: ids.file,
        mediaId: ids.media,
        replayed: false,
      });
    const reject = vi
      .fn<LegalOriginalUploadVerificationRepository["reject"]>()
      .mockResolvedValue(undefined);
    const value: LegalOriginalUploadVerificationRepository = {
      complete,
      load: vi.fn().mockResolvedValue({
        actorUserId: ids.user,
        bucket: "media-private",
        expectedByteSize: bytes.byteLength,
        expectedChecksumSha256: checksum,
        expectedMimeType: "application/pdf",
        mediaKind: "legal_document",
        objectKey: `workspaces/${ids.workspace}/documents/${ids.document}/upload-intents/${ids.session}/source`,
      }),
      reject,
    };
    return { complete, reject, value };
  }

  function scanner(
    verdict: "clean" | "infected" = "clean",
  ): MediaMalwareScanner {
    return {
      scan: vi.fn().mockResolvedValue({
        scanner: { name: "clamd", version: "1.4.2" },
        signatureVersion: "27345",
        sourceChecksumSha256: checksum,
        verdict,
      }),
    };
  }

  it("derives byte provenance, scans first and records an immutable receipt", async () => {
    const repo = repository();
    const result = await createLegalOriginalUploadVerificationJobHandler({
      repository: repo.value,
      scanner: scanner(),
      storage: storage(),
      workerId: "legal-worker-1",
    })(job, { signal: new AbortController().signal });
    expect(result?.summary).toMatchObject({
      media_file_id: ids.file,
      media_id: ids.media,
      upload_session_id: ids.session,
    });
    expect(repo.complete).toHaveBeenCalledWith(
      expect.objectContaining({
        observedByteSize: 1_000,
        observedChecksumSha256: checksum,
        observedMimeType: "application/pdf",
        storageGeneration: "etag-1",
        verificationReceipt: expect.objectContaining({
          schemaVersion: 1,
          storage: expect.objectContaining({ generation: "etag-1" }),
        }),
      }),
    );
  });

  it("scans before signature interpretation and records malware rejection", async () => {
    const repo = repository();
    bytes.fill(0);
    checksum = await mediaSha256Hex(bytes);
    await expect(
      createLegalOriginalUploadVerificationJobHandler({
        repository: repo.value,
        scanner: scanner("infected"),
        storage: storage(),
        workerId: "legal-worker-1",
      })(job, { signal: new AbortController().signal }),
    ).rejects.toMatchObject({
      classification: "validation",
      code: "media.malware_detected",
    });
    expect(repo.reject).toHaveBeenCalledWith(
      expect.objectContaining({ errorCode: "media.malware_detected" }),
    );
    expect(repo.complete).not.toHaveBeenCalled();
  });

  it("rejects provider MIME drift after a clean scan", async () => {
    const repo = repository();
    const drifted: LegalOriginalObjectStorage = {
      readLegalOriginal: vi.fn().mockResolvedValue({
        generation: "etag-1",
        providerMimeType: "image/png",
        source: bytes,
      }),
    };
    await expect(
      createLegalOriginalUploadVerificationJobHandler({
        repository: repo.value,
        scanner: scanner(),
        storage: drifted,
        workerId: "legal-worker-1",
      })(job, { signal: new AbortController().signal }),
    ).rejects.toMatchObject({ code: "media.invalid_legal_original" });
    expect(repo.reject).toHaveBeenCalledOnce();
  });

  it("leaves transient scanner outages for durable retry without rejection", async () => {
    const repo = repository();
    const unavailable: MediaMalwareScanner = {
      scan: vi.fn().mockRejectedValue(
        new JobExecutionError({
          classification: "transient",
          code: "media.malware_scanner_unavailable",
          safeDetail: "The private malware scanner is unavailable.",
        }),
      ),
    };
    await expect(
      createLegalOriginalUploadVerificationJobHandler({
        repository: repo.value,
        scanner: unavailable,
        storage: storage(),
        workerId: "legal-worker-1",
      })(job, { signal: new AbortController().signal }),
    ).rejects.toMatchObject({ classification: "transient" });
    expect(repo.reject).not.toHaveBeenCalled();
  });
});
