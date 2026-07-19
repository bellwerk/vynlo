import {
  buildVehiclePhotoProcessingJobPayload,
  createVehiclePhotoProcessingProfileSnapshot,
  type ManagedObjectStorage,
  type MediaMalwareScanner,
} from "@vynlo/media";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ClaimedJob } from "./job-store";
import {
  createVehiclePhotoJobHandler,
  type MediaProcessingRepository,
  type VehiclePhotoBinaryProcessor,
} from "./media-handler";
import { mediaSha256Hex } from "./managed-media-storage";

const ids = {
  correlation: "a9000000-0000-4000-8000-000000000006",
  job: "a9000000-0000-4000-8000-000000000004",
  lease: "a9000000-0000-4000-8000-000000000005",
  media: "a9000000-0000-4000-8000-000000000002",
  run: "a9000000-0000-4000-8000-000000000003",
  source: "a9000000-0000-4000-8000-000000000007",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;
const workerId = "media-worker.fixture-01";
const sourceBytes = new Uint8Array([0xff, 0xd8, 0xff, 1, 2, 3, 4, 5]);

describe("T-MED-001 / T-MED-002 / T-MED-003 / T-MED-004 vehicle photo worker", () => {
  let profile: Awaited<
    ReturnType<typeof createVehiclePhotoProcessingProfileSnapshot>
  >;
  let sourceChecksum: string;
  let job: ClaimedJob;

  beforeEach(async () => {
    profile = await createVehiclePhotoProcessingProfileSnapshot({
      profileKey: "vehicle_photo.default",
      version: 1,
    });
    sourceChecksum = await mediaSha256Hex(sourceBytes);
    job = {
      attemptNumber: 1,
      causationId: null,
      correlationId: ids.correlation,
      entityId: ids.media,
      entityType: "vehicle_media",
      idempotencyKey: `media:process:${ids.run}`,
      jobId: ids.job,
      jobType: "media.process_vehicle_photo",
      leaseExpiresAt: "2099-01-01T00:00:00.000Z",
      leaseToken: ids.lease,
      maximumAttempts: 8,
      outboxEventId: "a9000000-0000-4000-8000-000000000008",
      payload: {
        ...buildVehiclePhotoProcessingJobPayload({
          mediaId: ids.media,
          processingRunId: ids.run,
          profileChecksumSha256: profile.checksumSha256,
          source: { id: ids.source, kind: "upload_session" },
        }),
      },
      payloadSchemaVersion: 1,
      workspaceId: ids.workspace,
    };
  });

  it("scans, normalizes, stores deterministic outputs, and exact-lease completes", async () => {
    const start = vi
      .fn<MediaProcessingRepository["start"]>()
      .mockResolvedValue({
        alreadySucceeded: false,
        bucket: "media-private",
        byteSize: sourceBytes.byteLength,
        checksumSha256: sourceChecksum,
        exifOrientation: 6,
        generation: 1,
        height: 50,
        mediaStatus: "processing",
        mimeType: "image/jpeg",
        objectKey: `workspaces/${ids.workspace}/uploads/${ids.source}/source`,
        profile,
        width: 100,
      });
    const complete = vi
      .fn<MediaProcessingRepository["complete"]>()
      .mockResolvedValue({
        aggregateVersion: 3,
        mediaStatus: "ready",
        normalizedMasterFileId: "a9000000-0000-4000-8000-000000000011",
        rawDeleteAfter: "2099-01-08T00:00:00.000Z",
        rawFileId: "a9000000-0000-4000-8000-000000000010",
        replayed: false,
      });
    const repository: MediaProcessingRepository = {
      complete,
      recordFailure: vi.fn(),
      start,
    };
    const scanner: MediaMalwareScanner = {
      scan: vi.fn().mockResolvedValue({
        scanner: { name: "fixture-scan", version: "1.0.0" },
        signatureVersion: "fixture-1",
        sourceChecksumSha256: sourceChecksum,
        verdict: "clean",
      }),
    };
    const processor: VehiclePhotoBinaryProcessor = {
      async process(input) {
        const outputBodies = await Promise.all(
          input.derivativePlan.map(async (planned, index) => {
            const body = new Uint8Array([index + 1, index + 10]);
            return { body, checksum: await mediaSha256Hex(body), planned };
          }),
        );
        return {
          outputs: outputBodies.map(({ body, planned }) => ({
            body,
            variant: planned.variant,
          })),
          receipt: {
            outputs: outputBodies.map(({ body, checksum, planned }) => ({
              byteSize: body.byteLength,
              checksumSha256: checksum,
              height: planned.height,
              metadata: {
                exifPresent: false,
                gpsPresent: false,
                iptcPresent: false,
                xmpPresent: false,
              },
              mimeType: "image/webp",
              normalizedOrientation: 1,
              orientationPolicyApplied: true,
              outputColorSpace: "srgb",
              role: planned.role,
              upscaled: false,
              variant: planned.variant,
              width: planned.width,
            })),
            processor: { name: "fixture-codec", version: "1.0.0" },
            profileChecksumSha256: profile.checksumSha256,
            sourceChecksumSha256: sourceChecksum,
          },
        };
      },
    };
    const stored = new Map<string, Uint8Array>();
    const storage: ManagedObjectStorage = {
      createDownloadGrant: vi.fn(),
      createUploadGrant: vi.fn(),
      delete: vi.fn(),
      head: vi.fn(),
      read: vi.fn().mockResolvedValue(sourceBytes),
      async putIfAbsent(write) {
        const body = write.body as Uint8Array;
        expect(await mediaSha256Hex(body)).toBe(write.checksumSha256);
        stored.set(write.object.objectKey, body);
        return {
          ...write.object,
          byteSize: write.byteSize,
          checksumSha256: write.checksumSha256,
          mimeType: write.mimeType,
        };
      },
    };
    const handler = createVehiclePhotoJobHandler({
      processor,
      repository,
      scanner,
      storage,
      workerId,
    });

    const result = await handler(job, { signal: new AbortController().signal });

    expect(result?.summary).toMatchObject({
      aggregate_version: 3,
      media_id: ids.media,
      media_status: "ready",
      replayed: false,
    });
    expect(stored).toHaveLength(5);
    expect([...stored.keys()]).toEqual(
      expect.arrayContaining([
        expect.stringContaining(
          `/media/${ids.media}/raw/${sourceChecksum}.jpg`,
        ),
        expect.stringContaining(`/runs/${ids.run}/normalized_master/`),
        expect.stringContaining(`/runs/${ids.run}/website_1080/`),
      ]),
    );
    expect(complete).toHaveBeenCalledWith(
      expect.objectContaining({
        attemptNumber: 1,
        jobId: ids.job,
        leaseToken: ids.lease,
        mediaId: ids.media,
        processingRunId: ids.run,
        workerId,
      }),
    );
  });

  it("records an infected quarantine failure before the generic retry lifecycle", async () => {
    const recordFailure = vi
      .fn<MediaProcessingRepository["recordFailure"]>()
      .mockResolvedValue();
    const repository: MediaProcessingRepository = {
      complete: vi.fn(),
      recordFailure,
      start: vi.fn().mockResolvedValue({
        alreadySucceeded: false,
        bucket: "media-private",
        byteSize: sourceBytes.byteLength,
        checksumSha256: sourceChecksum,
        exifOrientation: null,
        generation: 1,
        height: 50,
        mediaStatus: "processing",
        mimeType: "image/jpeg",
        objectKey: `workspaces/${ids.workspace}/uploads/${ids.source}/source`,
        profile,
        width: 100,
      }),
    };
    const handler = createVehiclePhotoJobHandler({
      processor: { process: vi.fn() },
      repository,
      scanner: {
        scan: vi.fn().mockResolvedValue({
          scanner: { name: "fixture-scan", version: "1.0.0" },
          signatureVersion: "fixture-1",
          sourceChecksumSha256: sourceChecksum,
          verdict: "infected",
        }),
      },
      storage: {
        createDownloadGrant: vi.fn(),
        createUploadGrant: vi.fn(),
        delete: vi.fn(),
        head: vi.fn(),
        putIfAbsent: vi.fn(),
        read: vi.fn().mockResolvedValue(sourceBytes),
      },
      workerId,
    });

    await expect(
      handler(job, { signal: new AbortController().signal }),
    ).rejects.toMatchObject({
      classification: "validation",
      code: "media.malware_detected",
    });
    expect(recordFailure).toHaveBeenCalledWith(
      expect.objectContaining({
        classification: "validation",
        errorCode: "media.malware_detected",
        leaseToken: ids.lease,
        workerId,
      }),
    );
  });
});
