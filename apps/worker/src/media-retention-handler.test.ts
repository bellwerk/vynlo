import { describe, expect, it, vi } from "vitest";

import type { ClaimedJob } from "./job-store";
import {
  createRawRetentionJobHandler,
  type RawRetentionRepository,
} from "./media-handler";
import { SupabaseManagedMediaStorage } from "./managed-media-storage";

const ids = {
  correlation: "a9000000-0000-4000-8000-000000000001",
  file: "a9000000-0000-4000-8000-000000000002",
  job: "a9000000-0000-4000-8000-000000000003",
  lease: "a9000000-0000-4000-8000-000000000004",
  media: "a9000000-0000-4000-8000-000000000005",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;

describe("T-MED-002 vehicle raw retention worker", () => {
  it("fails closed before provider I/O when atomic conditional delete is unavailable", async () => {
    const repository: RawRetentionRepository = {
      complete: vi.fn(),
      load: vi.fn().mockResolvedValue({
        alreadyDeleted: false,
        checksumSha256: "a".repeat(64),
        mediaId: ids.media,
        storageBucket: "media-private",
        storageObjectKey: `workspaces/${ids.workspace}/media/${ids.media}/raw/${"a".repeat(64)}.jpg`,
      }),
    };
    const providerRequest = vi.fn<typeof fetch>();
    const storage = new SupabaseManagedMediaStorage({
      fetchImplementation: providerRequest,
      serviceRoleKey: "service-role-key-that-is-server-only",
      supabaseUrl: "https://storage.example.invalid",
    });
    const job: ClaimedJob = {
      attemptNumber: 1,
      causationId: null,
      correlationId: ids.correlation,
      entityId: ids.file,
      entityType: "media_file",
      idempotencyKey: `media:retention:${ids.file}`,
      jobId: ids.job,
      jobType: "media.delete_retained_raw",
      leaseExpiresAt: "2099-01-01T00:00:00.000Z",
      leaseToken: ids.lease,
      maximumAttempts: 8,
      outboxEventId: "a9000000-0000-4000-8000-000000000006",
      payload: { media_file_id: ids.file, media_id: ids.media },
      payloadSchemaVersion: 1,
      workspaceId: ids.workspace,
    };

    await expect(
      createRawRetentionJobHandler({
        repository,
        storage,
        workerId: "media-worker.fixture-01",
      })(job, { signal: new AbortController().signal }),
    ).rejects.toMatchObject({
      classification: "permanent",
      code: "media.storage_atomic_delete_unsupported",
    });
    expect(providerRequest).not.toHaveBeenCalled();
    expect(repository.complete).not.toHaveBeenCalled();
  });
});
