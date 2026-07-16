import type { ManagedObjectStorage } from "@vynlo/media";
import { describe, expect, it, vi } from "vitest";

import type { ClaimedJob } from "./job-store";
import {
  createMediaQuarantineCleanupJobHandler,
  type MediaQuarantineCleanupRepository,
} from "./media-quarantine-cleanup-handler";

const ids = {
  cleanup: "a9000000-0000-4000-8000-000000000001",
  correlation: "a9000000-0000-4000-8000-000000000002",
  job: "a9000000-0000-4000-8000-000000000003",
  lease: "a9000000-0000-4000-8000-000000000004",
  media: "a9000000-0000-4000-8000-000000000005",
  session: "a9000000-0000-4000-8000-000000000006",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;
const checksum = "a".repeat(64);
const workerId = "media-worker.fixture-01";

function job(): ClaimedJob {
  return {
    attemptNumber: 1,
    causationId: null,
    correlationId: ids.correlation,
    entityId: ids.session,
    entityType: "media_upload_session",
    idempotencyKey: `media:quarantine-cleanup:${ids.session}`,
    jobId: ids.job,
    jobType: "media.delete_quarantine_upload",
    leaseExpiresAt: "2099-01-01T00:00:00.000Z",
    leaseToken: ids.lease,
    maximumAttempts: 8,
    outboxEventId: "a9000000-0000-4000-8000-000000000007",
    payload: {
      checksum_sha256: checksum,
      generation: 1,
      media_id: ids.media,
      reason: "verified_raw_copy",
      upload_session_id: ids.session,
    },
    payloadSchemaVersion: 1,
    workspaceId: ids.workspace,
  };
}

function repository(): MediaQuarantineCleanupRepository {
  return {
    complete: vi.fn().mockResolvedValue({
      cleanupId: ids.cleanup,
      cleanupStatus: "deleted",
      completedAt: "2099-01-01T00:00:00.000Z",
      mediaId: ids.media,
      replayed: false,
    }),
    fenceChecksum: vi.fn().mockResolvedValue({
      checksumSha256: checksum,
      cleanupId: ids.cleanup,
      replayed: false,
    }),
    load: vi.fn().mockResolvedValue({
      alreadyDeleted: false,
      bucket: "media-private",
      cleanupId: ids.cleanup,
      expectedChecksumSha256: checksum,
      generation: 1,
      mediaId: ids.media,
      objectKey: `workspaces/${ids.workspace}/uploads/${ids.session}/source`,
      reason: "verified_raw_copy",
    }),
  };
}

describe("T-MED-003 / T-MED-004 media quarantine cleanup worker", () => {
  it("rejects an unstable worker identity before accepting jobs", () => {
    expect(() =>
      createMediaQuarantineCleanupJobHandler({
        repository: repository(),
        storage: {
          createDownloadGrant: vi.fn(),
          createUploadGrant: vi.fn(),
          delete: vi.fn(),
          head: vi.fn(),
          putIfAbsent: vi.fn(),
          read: vi.fn(),
        },
        workerId: "contains a space",
      }),
    ).toThrow(/stable non-secret identifier/u);
  });

  it("fences and atomically deletes only the exact quarantine object", async () => {
    const repo = repository();
    const storage: ManagedObjectStorage = {
      createDownloadGrant: vi.fn(),
      createUploadGrant: vi.fn(),
      delete: vi.fn().mockResolvedValue("deleted"),
      head: vi.fn().mockResolvedValue({
        bucket: "media-private",
        byteSize: 321,
        checksumSha256: checksum,
        mimeType: "image/jpeg",
        objectKey: `workspaces/${ids.workspace}/uploads/${ids.session}/source`,
      }),
      putIfAbsent: vi.fn(),
      read: vi.fn(),
    };
    const handler = createMediaQuarantineCleanupJobHandler({
      repository: repo,
      storage,
      workerId,
    });

    await expect(
      handler(job(), { signal: new AbortController().signal }),
    ).resolves.toMatchObject({
      summary: { cleanup_status: "deleted", media_id: ids.media },
    });
    expect(repo.fenceChecksum).toHaveBeenCalledWith(
      expect.objectContaining({
        observedByteSize: 321,
        observedChecksumSha256: checksum,
        uploadSessionId: ids.session,
        workspaceId: ids.workspace,
      }),
    );
    expect(storage.delete).toHaveBeenCalledWith(
      expect.objectContaining({
        ifChecksumSha256: checksum,
        object: {
          bucket: "media-private",
          objectKey: `workspaces/${ids.workspace}/uploads/${ids.session}/source`,
        },
      }),
    );
  });

  it("records an already absent exact object without attempting deletion", async () => {
    const repo = repository();
    vi.mocked(repo.complete).mockResolvedValue({
      cleanupId: ids.cleanup,
      cleanupStatus: "not_found",
      completedAt: "2099-01-01T00:00:00.000Z",
      mediaId: ids.media,
      replayed: false,
    });
    const storage: ManagedObjectStorage = {
      createDownloadGrant: vi.fn(),
      createUploadGrant: vi.fn(),
      delete: vi.fn(),
      head: vi.fn().mockResolvedValue(null),
      putIfAbsent: vi.fn(),
      read: vi.fn(),
    };
    const handler = createMediaQuarantineCleanupJobHandler({
      repository: repo,
      storage,
      workerId,
    });

    await handler(job(), { signal: new AbortController().signal });

    expect(storage.delete).not.toHaveBeenCalled();
    expect(repo.fenceChecksum).not.toHaveBeenCalled();
    expect(repo.complete).toHaveBeenCalledWith(
      expect.objectContaining({
        objectChecksumSha256: null,
        storageResult: "not_found",
      }),
    );
  });

  it("fails closed when an object is replaced between inspection and atomic deletion", async () => {
    const repo = repository();
    const storage: ManagedObjectStorage = {
      createDownloadGrant: vi.fn(),
      createUploadGrant: vi.fn(),
      delete: vi.fn().mockResolvedValue("precondition_failed"),
      head: vi.fn().mockResolvedValue({
        bucket: "media-private",
        byteSize: 321,
        checksumSha256: checksum,
        mimeType: "image/jpeg",
        objectKey: `workspaces/${ids.workspace}/uploads/${ids.session}/source`,
      }),
      putIfAbsent: vi.fn(),
      read: vi.fn(),
    };
    const handler = createMediaQuarantineCleanupJobHandler({
      repository: repo,
      storage,
      workerId,
    });

    await expect(
      handler(job(), { signal: new AbortController().signal }),
    ).rejects.toMatchObject({
      classification: "permanent",
      code: "media.quarantine_cleanup_atomic_precondition_failed",
    });
    expect(repo.fenceChecksum).toHaveBeenCalledTimes(1);
    expect(repo.complete).not.toHaveBeenCalled();
  });

  it("rejects workspace/session generation substitution before storage access", async () => {
    const repo = repository();
    vi.mocked(repo.load).mockResolvedValue({
      alreadyDeleted: false,
      bucket: "media-private",
      cleanupId: ids.cleanup,
      expectedChecksumSha256: checksum,
      generation: 2,
      mediaId: ids.media,
      objectKey: `workspaces/${ids.workspace}/uploads/${ids.session}/source`,
      reason: "verified_raw_copy",
    });
    const storage: ManagedObjectStorage = {
      createDownloadGrant: vi.fn(),
      createUploadGrant: vi.fn(),
      delete: vi.fn(),
      head: vi.fn(),
      putIfAbsent: vi.fn(),
      read: vi.fn(),
    };

    await expect(
      createMediaQuarantineCleanupJobHandler({
        repository: repo,
        storage,
        workerId,
      })(job(), { signal: new AbortController().signal }),
    ).rejects.toMatchObject({
      code: "media.quarantine_cleanup_fence_mismatch",
    });
    expect(storage.head).not.toHaveBeenCalled();
  });
});
