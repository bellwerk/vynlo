import { describe, expect, it, vi } from "vitest";

import { PostgrestMediaRepository } from "./media-repository";

const ids = {
  cleanup: "a9000000-0000-4000-8000-000000000001",
  correlation: "a9000000-0000-4000-8000-000000000002",
  job: "a9000000-0000-4000-8000-000000000003",
  lease: "a9000000-0000-4000-8000-000000000004",
  session: "a9000000-0000-4000-8000-000000000005",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;
const signal = new AbortController().signal;

function repository(request: typeof fetch) {
  return new PostgrestMediaRepository({
    fetchImplementation: request,
    serviceRoleKey: "service-role-key-that-is-server-only",
    supabaseUrl: "https://database.example.invalid",
  }).legalOriginalQuarantineCleanupRepository();
}

describe("T-MED-002 / T-MED-003 Postgrest legal original quarantine cleanup repository", () => {
  it("loads only the exact lease-bound private key and reason", async () => {
    const request = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json([
        {
          already_deleted: false,
          cleanup_id: ids.cleanup,
          cleanup_reason: "terminal_rejection",
          storage_bucket: "media-private",
          storage_object_key: "workspaces/one/legal/source",
        },
      ]),
    );
    await expect(
      repository(request).load({
        attemptNumber: 1,
        jobId: ids.job,
        leaseToken: ids.lease,
        signal,
        uploadSessionId: ids.session,
        workerId: "legal-cleanup.fixture-01",
        workspaceId: ids.workspace,
      }),
    ).resolves.toEqual({
      alreadyDeleted: false,
      bucket: "media-private",
      cleanupId: ids.cleanup,
      objectKey: "workspaces/one/legal/source",
      reason: "terminal_rejection",
    });
  });

  it("sends exact observed provenance then terminal checksum", async () => {
    const request = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([{ cleanup_id: ids.cleanup, replayed: false }]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            cleanup_id: ids.cleanup,
            cleanup_status: "deleted",
            replayed: false,
          },
        ]),
      );
    const target = repository(request);
    await target.fence({
      attemptNumber: 1,
      jobId: ids.job,
      leaseToken: ids.lease,
      observedByteSize: 100,
      observedChecksumSha256: "a".repeat(64),
      observedMimeType: "application/pdf",
      signal,
      storageGeneration: "etag-1",
      uploadSessionId: ids.session,
      workerId: "legal-cleanup.fixture-01",
      workspaceId: ids.workspace,
    });
    await target.complete({
      attemptNumber: 1,
      correlationId: ids.correlation,
      jobId: ids.job,
      leaseToken: ids.lease,
      observedChecksumSha256: "a".repeat(64),
      requestId: "job:legal-cleanup",
      signal,
      storageResult: "deleted",
      uploadSessionId: ids.session,
      workerId: "legal-cleanup.fixture-01",
      workspaceId: ids.workspace,
    });
    expect(request.mock.calls.map(([url]) => String(url))).toEqual([
      expect.stringContaining("fence_legal_original_quarantine_cleanup"),
      expect.stringContaining("complete_legal_original_quarantine_cleanup"),
    ]);
    expect(JSON.parse(String(request.mock.calls[0]?.[1]?.body))).toMatchObject({
      p_observed_byte_size: 100,
      p_observed_mime_type: "application/pdf",
      p_storage_generation: "etag-1",
    });
  });
});
