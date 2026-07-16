import {
  buildVehiclePhotoUploadVerificationJobPayload,
  type ManagedObjectStorage,
  type MediaMalwareScanner,
} from "@vynlo/media";
import sharp from "sharp";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { ClaimedJob } from "./job-store";
import { JobExecutionError } from "./job-runner";
import { mediaSha256Hex } from "./managed-media-storage";
import {
  createMediaUploadVerificationJobHandler,
  type MediaUploadVerificationRepository,
} from "./media-upload-verification-handler";
import { inspectVehiclePhotoWithSharp } from "./sharp-vehicle-photo-processor";

const ids = {
  correlation: "b9000000-0000-4000-8000-000000000006",
  job: "b9000000-0000-4000-8000-000000000004",
  lease: "b9000000-0000-4000-8000-000000000005",
  media: "b9000000-0000-4000-8000-000000000002",
  processingJob: "b9000000-0000-4000-8000-000000000009",
  processingRun: "b9000000-0000-4000-8000-000000000008",
  session: "b9000000-0000-4000-8000-000000000007",
  user: "b9000000-0000-4000-8000-000000000010",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;

describe("T-MED-003 / T-MED-004 vehicle photo upload verification worker", () => {
  let checksum: string;
  let job: ClaimedJob;
  let source: Uint8Array;

  beforeEach(async () => {
    source = new Uint8Array(
      await sharp({
        create: {
          background: { alpha: 1, b: 30, g: 80, r: 160 },
          channels: 4,
          height: 4,
          width: 6,
        },
      })
        .png()
        .withMetadata({ orientation: 6 })
        .toBuffer(),
    );
    checksum = await mediaSha256Hex(source);
    job = {
      attemptNumber: 1,
      causationId: null,
      correlationId: ids.correlation,
      entityId: ids.session,
      entityType: "media_upload_session",
      idempotencyKey: `media:verify:${ids.session}:fixture`,
      jobId: ids.job,
      jobType: "media.verify_vehicle_photo_upload",
      leaseExpiresAt: "2099-01-01T00:00:00.000Z",
      leaseToken: ids.lease,
      maximumAttempts: 6,
      outboxEventId: "b9000000-0000-4000-8000-000000000011",
      payload: {
        ...buildVehiclePhotoUploadVerificationJobPayload({
          mediaId: ids.media,
          uploadSessionId: ids.session,
        }),
      },
      payloadSchemaVersion: 1,
      workspaceId: ids.workspace,
    };
  });

  function storage(): ManagedObjectStorage {
    return {
      createDownloadGrant: vi.fn(),
      createUploadGrant: vi.fn(),
      delete: vi.fn(),
      head: vi.fn(),
      putIfAbsent: vi.fn(),
      read: vi.fn().mockResolvedValue(source),
    };
  }

  function repository() {
    const complete = vi
      .fn<MediaUploadVerificationRepository["complete"]>()
      .mockResolvedValue({
        aggregateVersion: 3,
        mediaStatus: "quarantined",
        processingJobId: ids.processingJob,
        processingRunId: ids.processingRun,
        replayed: false,
      });
    const reject = vi
      .fn<MediaUploadVerificationRepository["reject"]>()
      .mockResolvedValue(undefined);
    const value: MediaUploadVerificationRepository = {
      complete,
      load: vi.fn().mockResolvedValue({
        actorUserId: ids.user,
        bucket: "media-private",
        expectedByteSize: source.byteLength,
        expectedChecksumSha256: checksum,
        expectedMimeType: "image/png",
        expiresAt: "2099-01-01T00:00:00.000Z",
        objectKey: `workspaces/${ids.workspace}/uploads/${ids.session}/source`,
      }),
      reject,
    };
    return { complete, reject, value };
  }

  it("derives trusted signature, orientation, dimensions and checksum before completion", async () => {
    const repo = repository();
    const scanner: MediaMalwareScanner = {
      scan: vi.fn().mockResolvedValue({
        scanner: { name: "clamd", version: "1.4.2" },
        signatureVersion: "27345",
        sourceChecksumSha256: checksum,
        verdict: "clean",
      }),
    };
    const result = await createMediaUploadVerificationJobHandler({
      repository: repo.value,
      scanner,
      storage: storage(),
      workerId: "media-worker-1",
    })(job, { signal: new AbortController().signal });

    expect(result?.summary).toMatchObject({
      aggregate_version: 3,
      media_status: "quarantined",
      processing_job_id: ids.processingJob,
    });
    expect(repo.complete).toHaveBeenCalledWith(
      expect.objectContaining({
        exifOrientation: 6,
        height: 6,
        observedByteSize: source.byteLength,
        observedChecksumSha256: checksum,
        observedMimeType: "image/png",
        width: 4,
      }),
    );
    expect(repo.reject).not.toHaveBeenCalled();
  });

  it("records a terminal rejection when malware is detected", async () => {
    const repo = repository();
    const inspect = vi.fn<typeof inspectVehiclePhotoWithSharp>();
    const scanner: MediaMalwareScanner = {
      scan: vi.fn().mockResolvedValue({
        scanner: { name: "clamd", version: "1.4.2" },
        signatureVersion: "27345",
        sourceChecksumSha256: checksum,
        verdict: "infected",
      }),
    };
    await expect(
      createMediaUploadVerificationJobHandler({
        inspect,
        repository: repo.value,
        scanner,
        storage: storage(),
        workerId: "media-worker-1",
      })(job, { signal: new AbortController().signal }),
    ).rejects.toMatchObject({
      classification: "validation",
      code: "media.malware_detected",
    });
    expect(repo.reject).toHaveBeenCalledWith(
      expect.objectContaining({
        errorClassification: "validation",
        errorCode: "media.malware_detected",
      }),
    );
    expect(repo.complete).not.toHaveBeenCalled();
    expect(inspect).not.toHaveBeenCalled();
  });

  it("leaves retryable scanner outages to durable job backoff", async () => {
    const repo = repository();
    const scanner: MediaMalwareScanner = {
      scan: vi.fn().mockRejectedValue(
        new JobExecutionError({
          classification: "transient",
          code: "media.malware_scanner_unavailable",
          safeDetail: "The private scanner is unavailable.",
        }),
      ),
    };
    await expect(
      createMediaUploadVerificationJobHandler({
        repository: repo.value,
        scanner,
        storage: storage(),
        workerId: "media-worker-1",
      })(job, { signal: new AbortController().signal }),
    ).rejects.toMatchObject({ classification: "transient" });
    expect(repo.reject).not.toHaveBeenCalled();
  });
});
