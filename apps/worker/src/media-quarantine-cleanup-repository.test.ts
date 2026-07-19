import { describe, expect, it, vi } from "vitest";

import { PostgrestMediaRepository } from "./media-repository";

const ids = {
  cleanup: "a9000000-0000-4000-8000-000000000001",
  correlation: "a9000000-0000-4000-8000-000000000002",
  job: "a9000000-0000-4000-8000-000000000003",
  lease: "a9000000-0000-4000-8000-000000000004",
  media: "a9000000-0000-4000-8000-000000000005",
  session: "a9000000-0000-4000-8000-000000000006",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;
const signal = new AbortController().signal;

describe("T-MED-003 / T-MED-004 PostgrestMediaRepository quarantine cleanup", () => {
  it("maps the exact cleanup source and sends only lease-bound identifiers", async () => {
    const request = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json([
        {
          already_deleted: false,
          cleanup_id: ids.cleanup,
          cleanup_reason: "verified_raw_copy",
          expected_checksum_sha256: "a".repeat(64),
          generation: 2,
          media_id: ids.media,
          storage_bucket: "media-private",
          storage_object_key: `workspaces/${ids.workspace}/uploads/${ids.session}/source`,
        },
      ]),
    );
    const repository = new PostgrestMediaRepository({
      fetchImplementation: request,
      serviceRoleKey: "service-role-key-that-is-server-only",
      supabaseUrl: "https://database.example.invalid",
    }).mediaQuarantineCleanupRepository();

    await expect(
      repository.load({
        attemptNumber: 1,
        jobId: ids.job,
        leaseToken: ids.lease,
        signal,
        uploadSessionId: ids.session,
        workerId: "media-worker.fixture-01",
        workspaceId: ids.workspace,
      }),
    ).resolves.toEqual({
      alreadyDeleted: false,
      bucket: "media-private",
      cleanupId: ids.cleanup,
      expectedChecksumSha256: "a".repeat(64),
      generation: 2,
      mediaId: ids.media,
      objectKey: `workspaces/${ids.workspace}/uploads/${ids.session}/source`,
      reason: "verified_raw_copy",
    });
    expect(JSON.parse(String(request.mock.calls[0]?.[1]?.body))).toEqual({
      p_attempt_number: 1,
      p_job_id: ids.job,
      p_lease_token: ids.lease,
      p_upload_session_id: ids.session,
      p_worker_id: "media-worker.fixture-01",
      p_workspace_id: ids.workspace,
    });
  });

  it("maps checksum fencing and terminal completion receipts", async () => {
    const request = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
          {
            checksum_sha256: "b".repeat(64),
            cleanup_id: ids.cleanup,
            replayed: false,
          },
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            cleanup_id: ids.cleanup,
            cleanup_status: "deleted",
            completed_at: "2099-01-01T00:00:00.000Z",
            media_id: ids.media,
            replayed: false,
          },
        ]),
      );
    const repository = new PostgrestMediaRepository({
      fetchImplementation: request,
      serviceRoleKey: "service-role-key-that-is-server-only",
      supabaseUrl: "https://database.example.invalid",
    }).mediaQuarantineCleanupRepository();
    const lease = {
      attemptNumber: 1,
      jobId: ids.job,
      leaseToken: ids.lease,
      signal,
      uploadSessionId: ids.session,
      workerId: "media-worker.fixture-01",
      workspaceId: ids.workspace,
    } as const;

    await expect(
      repository.fenceChecksum({
        ...lease,
        observedByteSize: 123,
        observedChecksumSha256: "b".repeat(64),
      }),
    ).resolves.toEqual({
      checksumSha256: "b".repeat(64),
      cleanupId: ids.cleanup,
      replayed: false,
    });
    await expect(
      repository.complete({
        ...lease,
        correlationId: ids.correlation,
        objectChecksumSha256: "b".repeat(64),
        requestId: `job:${ids.job}:cleanup`,
        storageResult: "deleted",
      }),
    ).resolves.toEqual({
      cleanupId: ids.cleanup,
      cleanupStatus: "deleted",
      completedAt: "2099-01-01T00:00:00.000Z",
      mediaId: ids.media,
      replayed: false,
    });
    expect(request.mock.calls.map(([url]) => String(url))).toEqual([
      expect.stringContaining("fence_media_quarantine_cleanup_checksum"),
      expect.stringContaining("complete_media_quarantine_cleanup"),
    ]);
  });

  it("rejects an unknown database reason before storage can be addressed", async () => {
    const request = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json([
        {
          already_deleted: false,
          cleanup_id: ids.cleanup,
          cleanup_reason: "legal_original",
          expected_checksum_sha256: null,
          generation: 1,
          media_id: ids.media,
          storage_bucket: "media-private",
          storage_object_key: "unexpected",
        },
      ]),
    );
    const repository = new PostgrestMediaRepository({
      fetchImplementation: request,
      serviceRoleKey: "service-role-key-that-is-server-only",
      supabaseUrl: "https://database.example.invalid",
    }).mediaQuarantineCleanupRepository();

    await expect(
      repository.load({
        attemptNumber: 1,
        jobId: ids.job,
        leaseToken: ids.lease,
        signal,
        uploadSessionId: ids.session,
        workerId: "media-worker.fixture-01",
        workspaceId: ids.workspace,
      }),
    ).rejects.toMatchObject({
      code: "media.invalid_quarantine_cleanup_reason",
    });
  });
});
