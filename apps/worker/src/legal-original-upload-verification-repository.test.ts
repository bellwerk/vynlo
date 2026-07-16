import { describe, expect, it, vi } from "vitest";

import { buildLegalOriginalVerificationReceipt } from "@vynlo/media";
import { PostgrestMediaRepository } from "./media-repository";

const ids = {
  correlation: "a9000000-0000-4000-8000-000000000002",
  document: "a9000000-0000-4000-8000-000000000007",
  file: "a9000000-0000-4000-8000-000000000008",
  job: "a9000000-0000-4000-8000-000000000003",
  lease: "a9000000-0000-4000-8000-000000000004",
  media: "a9000000-0000-4000-8000-000000000005",
  session: "a9000000-0000-4000-8000-000000000006",
  user: "a9000000-0000-4000-8000-000000000009",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;
const signal = new AbortController().signal;
const checksum = "a".repeat(64);

function repository(request: typeof fetch) {
  return new PostgrestMediaRepository({
    fetchImplementation: request,
    serviceRoleKey: "service-role-key-that-is-server-only",
    supabaseUrl: "https://database.example.invalid",
  }).legalOriginalUploadVerificationRepository();
}

describe("T-MED-002 / T-MED-003 PostgrestMediaRepository legal original verification", () => {
  it("loads exact lease-bound expected provenance", async () => {
    const request = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json([
        {
          actor_user_id: ids.user,
          expected_byte_size: 1_000,
          expected_checksum_sha256: checksum,
          expected_mime_type: "application/pdf",
          media_kind: "legal_document",
          upload_bucket: "media-private",
          upload_object_key: `workspaces/${ids.workspace}/documents/${ids.document}/upload-intents/${ids.session}/source`,
        },
      ]),
    );
    await expect(
      repository(request).load({
        attemptNumber: 1,
        correlationId: ids.correlation,
        documentId: ids.document,
        jobId: ids.job,
        leaseToken: ids.lease,
        requestId: `job:${ids.job}:load`,
        signal,
        uploadSessionId: ids.session,
        workerId: "legal-worker-1",
        workspaceId: ids.workspace,
      }),
    ).resolves.toMatchObject({
      bucket: "media-private",
      expectedByteSize: 1_000,
      expectedMimeType: "application/pdf",
      mediaKind: "legal_document",
    });
    expect(JSON.parse(String(request.mock.calls[0]?.[1]?.body))).toEqual({
      p_attempt_number: 1,
      p_document_id: ids.document,
      p_job_id: ids.job,
      p_lease_token: ids.lease,
      p_upload_session_id: ids.session,
      p_worker_id: "legal-worker-1",
      p_workspace_id: ids.workspace,
    });
  });

  it("sends the immutable receipt and maps completion identifiers", async () => {
    const request = vi
      .fn<typeof fetch>()
      .mockResolvedValue(
        Response.json([
          { media_file_id: ids.file, media_id: ids.media, replayed: false },
        ]),
      );
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
      objectKey: `workspaces/${ids.workspace}/documents/${ids.document}/upload-intents/${ids.session}/source`,
      workerId: "legal-worker-1",
    });
    await expect(
      repository(request).complete({
        attemptNumber: 1,
        correlationId: ids.correlation,
        documentId: ids.document,
        jobId: ids.job,
        leaseToken: ids.lease,
        observedByteSize: 1_000,
        observedChecksumSha256: checksum,
        observedMimeType: "application/pdf",
        requestId: `job:${ids.job}:complete`,
        signal,
        storageGeneration: "etag-1",
        uploadSessionId: ids.session,
        verificationReceipt: receipt,
        workerId: "legal-worker-1",
        workspaceId: ids.workspace,
      }),
    ).resolves.toEqual({
      mediaFileId: ids.file,
      mediaId: ids.media,
      replayed: false,
    });
    expect(JSON.parse(String(request.mock.calls[0]?.[1]?.body))).toMatchObject({
      p_document_id: ids.document,
      p_observed_byte_size: 1_000,
      p_storage_generation: "etag-1",
      p_verification_receipt: receipt,
    });
  });

  it("fails closed on unsupported database media kind", async () => {
    const request = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json([
        {
          actor_user_id: ids.user,
          expected_byte_size: 1_000,
          expected_checksum_sha256: checksum,
          expected_mime_type: "application/pdf",
          media_kind: "attachment",
          upload_bucket: "media-private",
          upload_object_key: "unexpected",
        },
      ]),
    );
    await expect(
      repository(request).load({
        attemptNumber: 1,
        correlationId: ids.correlation,
        documentId: ids.document,
        jobId: ids.job,
        leaseToken: ids.lease,
        requestId: "load",
        signal,
        uploadSessionId: ids.session,
        workerId: "legal-worker-1",
        workspaceId: ids.workspace,
      }),
    ).rejects.toMatchObject({
      code: "media.invalid_legal_original_media_kind",
    });
  });
});
