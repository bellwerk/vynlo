import { describe, expect, it, vi } from "vitest";

import { buildLegalOriginalQuarantineCleanupJobPayload } from "@vynlo/media";
import {
  createLegalOriginalQuarantineCleanupJobHandler,
  type LegalOriginalQuarantineCleanupRepository,
} from "./legal-original-quarantine-cleanup-handler";

const ids = {
  cleanup: "a9000000-0000-4000-8000-000000000001",
  correlation: "a9000000-0000-4000-8000-000000000002",
  job: "a9000000-0000-4000-8000-000000000003",
  lease: "a9000000-0000-4000-8000-000000000004",
  session: "a9000000-0000-4000-8000-000000000005",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;
const checksum =
  "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb";

function job(
  reason: "expired_intent" | "terminal_rejection" = "expired_intent",
) {
  return {
    attemptNumber: 1,
    causationId: null,
    correlationId: ids.correlation,
    entityId: ids.session,
    entityType: "legal_original_upload_session",
    idempotencyKey: `legal-cleanup:${ids.session}`,
    jobId: ids.job,
    jobType: "media.delete_legal_original_quarantine",
    leaseExpiresAt: "2099-01-01T00:00:00.000Z",
    leaseToken: ids.lease,
    maximumAttempts: 6,
    outboxEventId: "a9000000-0000-4000-8000-000000000006",
    payload: {
      ...buildLegalOriginalQuarantineCleanupJobPayload({
        reason,
        uploadSessionId: ids.session,
      }),
    },
    payloadSchemaVersion: 1,
    workspaceId: ids.workspace,
  } as const;
}

function repository(): LegalOriginalQuarantineCleanupRepository {
  return {
    complete: vi.fn().mockResolvedValue({
      cleanupId: ids.cleanup,
      cleanupStatus: "deleted",
      replayed: false,
    }),
    fence: vi
      .fn()
      .mockResolvedValue({ cleanupId: ids.cleanup, replayed: false }),
    load: vi.fn().mockResolvedValue({
      alreadyDeleted: false,
      bucket: "media-private",
      cleanupId: ids.cleanup,
      objectKey: `workspaces/${ids.workspace}/documents/original/source`,
      reason: "expired_intent",
    }),
  };
}

describe("T-MED-002 / T-MED-003 legal original quarantine cleanup", () => {
  it("fences generation, checksum, MIME and size before conditional delete", async () => {
    const repo = repository();
    const storage = {
      createDownloadGrant: vi.fn(),
      createUploadGrant: vi.fn(),
      delete: vi.fn().mockResolvedValue("deleted"),
      head: vi.fn().mockResolvedValue({
        bucket: "media-private",
        byteSize: 1,
        checksumSha256: checksum,
        mimeType: "application/pdf",
        objectKey: `workspaces/${ids.workspace}/documents/original/source`,
      }),
      putIfAbsent: vi.fn(),
      read: vi.fn(),
      readLegalOriginal: vi.fn().mockResolvedValue({
        generation: "etag-1",
        providerMimeType: "application/pdf",
        source: new Uint8Array([0x61]),
      }),
    };
    const result = await createLegalOriginalQuarantineCleanupJobHandler({
      repository: repo,
      storage,
      workerId: "legal-cleanup.fixture-01",
    })(job(), { signal: new AbortController().signal });
    expect(repo.fence).toHaveBeenCalledWith(
      expect.objectContaining({
        observedByteSize: 1,
        observedChecksumSha256: checksum,
        observedMimeType: "application/pdf",
        storageGeneration: "etag-1",
      }),
    );
    expect(storage.delete).toHaveBeenCalledWith(
      expect.objectContaining({ ifChecksumSha256: checksum }),
    );
    expect(result).toMatchObject({ summary: { cleanup_status: "deleted" } });
  });

  it("records not-found without attempting deletion", async () => {
    const repo = repository();
    vi.mocked(repo.complete).mockResolvedValue({
      cleanupId: ids.cleanup,
      cleanupStatus: "not_found",
      replayed: false,
    });
    const storage = {
      createDownloadGrant: vi.fn(),
      createUploadGrant: vi.fn(),
      delete: vi.fn(),
      head: vi.fn().mockResolvedValue(null),
      putIfAbsent: vi.fn(),
      read: vi.fn(),
      readLegalOriginal: vi.fn(),
    };
    await createLegalOriginalQuarantineCleanupJobHandler({
      repository: repo,
      storage,
      workerId: "legal-cleanup.fixture-01",
    })(job(), { signal: new AbortController().signal });
    expect(repo.complete).toHaveBeenCalledWith(
      expect.objectContaining({
        observedChecksumSha256: null,
        storageResult: "not_found",
      }),
    );
    expect(storage.delete).not.toHaveBeenCalled();
  });

  it("fails before storage when durable reason and database fence differ", async () => {
    const repo = repository();
    await expect(
      createLegalOriginalQuarantineCleanupJobHandler({
        repository: repo,
        storage: {
          createDownloadGrant: vi.fn(),
          createUploadGrant: vi.fn(),
          delete: vi.fn(),
          head: vi.fn(),
          putIfAbsent: vi.fn(),
          read: vi.fn(),
          readLegalOriginal: vi.fn(),
        },
        workerId: "legal-cleanup.fixture-01",
      })(job("terminal_rejection"), {
        signal: new AbortController().signal,
      }),
    ).rejects.toMatchObject({ code: "media.legal_cleanup_reason_mismatch" });
  });
});
