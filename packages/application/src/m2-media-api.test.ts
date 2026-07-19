import { describe, expect, it, vi } from "vitest";

import type { AuthenticatedRpcGateway } from "./vertical-slice-api";
import {
  M2MediaApplicationService,
  type M2MediaDownloadGrantPort,
  M2MediaRpcContractError,
  M2MediaValidationError,
} from "./m2-media-api";

const ids = {
  audit: "11000000-0000-4000-8000-000000000001",
  authorization: "11000000-0000-4000-8000-000000000002",
  correlation: "12000000-0000-4000-8000-000000000001",
  file: "13000000-0000-4000-8000-000000000001",
  file2: "13000000-0000-4000-8000-000000000002",
  inventory: "14000000-0000-4000-8000-000000000001",
  inventory2: "14000000-0000-4000-8000-000000000002",
  job: "15000000-0000-4000-8000-000000000001",
  job2: "15000000-0000-4000-8000-000000000002",
  media: "16000000-0000-4000-8000-000000000001",
  media2: "16000000-0000-4000-8000-000000000002",
  outbox: "17000000-0000-4000-8000-000000000001",
  profile: "17000000-0000-4000-8000-000000000002",
  run: "18000000-0000-4000-8000-000000000001",
  session: "19000000-0000-4000-8000-000000000001",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;

function command(body: unknown) {
  return {
    body,
    metadata: {
      accessToken: "user-access-token",
      correlationId: ids.correlation,
      idempotencyKey: "m2-media-command-001",
      requestId: "request-media-001",
      workspaceId: ids.workspace,
    },
  } as const;
}

function service(result: unknown, downloadGrants?: M2MediaDownloadGrantPort) {
  const invoke = vi
    .fn<AuthenticatedRpcGateway["invoke"]>()
    .mockResolvedValue(result);
  return {
    invoke,
    service: new M2MediaApplicationService({ invoke }, downloadGrants),
  };
}

function vehicleMediaAsset(
  overrides: Readonly<Record<string, unknown>> = {},
): Readonly<Record<string, unknown>> {
  return {
    archivedAt: null,
    caption: "Front three-quarter view",
    collectionVersion: 8,
    createdAt: "2026-07-16T12:00:00.000Z",
    files: [
      {
        byteSize: 1_024,
        checksumSha256: "c".repeat(64),
        createdAt: "2026-07-16T12:01:00.000Z",
        fileClass: "vehicle_photo_derivative",
        height: 213,
        id: ids.file,
        metadataStripped: true,
        mimeType: "image/webp",
        processingRunId: ids.run,
        status: "available",
        variant: "thumbnail_320",
        width: 320,
      },
    ],
    id: ids.media,
    inventoryUnitId: ids.inventory,
    isCover: true,
    mediaVersion: 4,
    processingProfile: {
      checksumSha256: "d".repeat(64),
      id: ids.profile,
      version: 1,
    },
    sortOrder: 0,
    status: "ready",
    updatedAt: "2026-07-16T12:02:00.000Z",
    ...overrides,
  };
}

describe("T-MED-003 / T-MED-004 / T-MED-005 / T-STOR-001 M2 media application service", () => {
  it("normalizes a bounded photo intent and returns an authenticated exact upload target", async () => {
    const fixture = service([
      {
        aggregate_version: 1,
        audit_event_id: ids.audit,
        collection_version: 2,
        expires_at: "2026-07-16T12:15:00.000Z",
        media_id: ids.media,
        outbox_event_id: ids.outbox,
        replayed: false,
        upload_bucket: "media-private",
        upload_object_key: `workspaces/${ids.workspace}/uploads/${ids.session}/source`,
        upload_session_id: ids.session,
      },
    ]);
    await expect(
      fixture.service.createUploadIntent({
        ...command({
          byteSize: 1_024,
          checksumSha256: "a".repeat(64),
          filename: " phone-photo.JPG ",
          mimeType: "image/jpeg",
        }),
        inventoryUnitId: ids.inventory,
      }),
    ).resolves.toMatchObject({
      mediaId: ids.media,
      upload: {
        bucket: "media-private",
        requiresAuthenticatedSession: true,
      },
      uploadSessionId: ids.session,
    });
    expect(fixture.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "create_vehicle_photo_upload_session",
        parameters: expect.objectContaining({
          p_byte_size: 1_024,
          p_filename: "phone-photo.JPG",
          p_inventory_unit_id: ids.inventory,
          p_mime_type: "image/jpeg",
          p_workspace_id: ids.workspace,
        }),
      }),
    );
  });

  it("requires a client-computed checksum before issuing an exact upload intent", async () => {
    const fixture = service([]);

    await expect(
      fixture.service.createUploadIntent({
        ...command({
          byteSize: 1_024,
          filename: "phone-photo.jpg",
          mimeType: "image/jpeg",
        }),
        inventoryUnitId: ids.inventory,
      }),
    ).rejects.toBeInstanceOf(M2MediaValidationError);
    expect(fixture.invoke).not.toHaveBeenCalled();
  });

  it("queues trusted upload verification without accepting client attestations", async () => {
    const fixture = service([
      {
        aggregate_version: 2,
        audit_event_id: ids.audit,
        job_id: ids.job,
        job_status: "queued",
        media_id: ids.media,
        outbox_event_id: ids.outbox,
        replayed: false,
        upload_session_id: ids.session,
      },
    ]);
    await expect(
      fixture.service.requestUploadVerification({
        ...command({ uploadSessionId: ids.session }),
        mediaId: ids.media,
      }),
    ).resolves.toMatchObject({ jobId: ids.job, jobStatus: "queued" });
    expect(fixture.invoke.mock.calls[0]?.[0].parameters).toEqual({
      p_correlation_id: ids.correlation,
      p_idempotency_key: "m2-media-command-001",
      p_media_id: ids.media,
      p_request_id: "request-media-001",
      p_upload_session_id: ids.session,
      p_workspace_id: ids.workspace,
    });
  });

  it("projects only bounded owner-safe upload status and retries the exact dead-letter job", async () => {
    const status = service([
      {
        attempt_count: 6,
        completed_at: null,
        error_classification: "transient",
        error_code: "media.storage_unavailable",
        job_id: ids.job,
        maximum_attempts: 6,
        media_id: ids.media,
        retry_at: null,
        retryable: true,
        status: "dead_letter",
        upload_session_id: ids.session,
      },
    ]);
    await expect(
      status.service.getUploadVerificationStatus({
        accessToken: "user-access-token",
        mediaId: ids.media,
        uploadSessionId: ids.session,
        workspaceId: ids.workspace,
      }),
    ).resolves.toEqual({
      completedAt: null,
      failure: {
        classification: "transient",
        code: "media.storage_unavailable",
      },
      job: {
        attemptCount: 6,
        id: ids.job,
        maximumAttempts: 6,
        retryAt: null,
      },
      mediaId: ids.media,
      retryable: true,
      status: "dead_letter",
      uploadSessionId: ids.session,
    });
    expect(status.invoke).toHaveBeenCalledWith({
      accessToken: "user-access-token",
      functionName: "get_vehicle_photo_upload_status",
      parameters: {
        p_media_id: ids.media,
        p_upload_session_id: ids.session,
        p_workspace_id: ids.workspace,
      },
    });

    const retry = service([
      {
        aggregate_version: 4,
        audit_event_id: ids.audit,
        job_id: ids.job2,
        job_status: "queued",
        media_id: ids.media,
        outbox_event_id: ids.outbox,
        replayed: false,
        source_job_id: ids.job,
        upload_session_id: ids.session,
      },
    ]);
    await expect(
      retry.service.retryUploadVerification({
        ...command({ reason: " Storage recovered. " }),
        mediaId: ids.media,
        uploadSessionId: ids.session,
      }),
    ).resolves.toMatchObject({
      jobId: ids.job2,
      sourceJobId: ids.job,
      uploadSessionId: ids.session,
    });
    expect(retry.invoke.mock.calls[0]?.[0]).toMatchObject({
      functionName: "retry_vehicle_photo_upload_verification",
      parameters: {
        p_correlation_id: ids.correlation,
        p_idempotency_key: "m2-media-command-001",
        p_media_id: ids.media,
        p_reason: "Storage recovered.",
        p_request_id: "request-media-001",
        p_upload_session_id: ids.session,
        p_workspace_id: ids.workspace,
      },
    });
  });

  it("fails closed on leaked upload status fields and mismatched retry identities", async () => {
    await expect(
      service([
        {
          attempt_count: 6,
          completed_at: null,
          error_classification: "transient",
          error_code: "media.storage_unavailable",
          job_id: ids.job,
          maximum_attempts: 6,
          media_id: ids.media,
          retry_at: null,
          retryable: true,
          status: "dead_letter",
          storage_object_key: "must-not-leak",
          upload_session_id: ids.session,
        },
      ]).service.getUploadVerificationStatus({
        accessToken: "user-access-token",
        mediaId: ids.media,
        uploadSessionId: ids.session,
        workspaceId: ids.workspace,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);

    await expect(
      service([
        {
          aggregate_version: 4,
          audit_event_id: ids.audit,
          job_id: ids.job2,
          job_status: "queued",
          media_id: ids.media2,
          outbox_event_id: ids.outbox,
          replayed: false,
          source_job_id: ids.job,
          upload_session_id: ids.session,
        },
      ]).service.retryUploadVerification({
        ...command({ reason: "Storage recovered." }),
        mediaId: ids.media,
        uploadSessionId: ids.session,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);
  });

  it("maps reprocess, reorder, and cover commands to optimistic versions", async () => {
    const reprocess = service([
      {
        aggregate_version: 5,
        audit_event_id: ids.audit,
        generation: 2,
        job_id: ids.job,
        media_id: ids.media,
        media_status: "quarantined",
        outbox_event_id: ids.outbox,
        processing_run_id: ids.run,
        replayed: false,
      },
    ]);
    await expect(
      reprocess.service.reprocess({
        ...command({ expectedVersion: 4, reason: "Retry corrected file" }),
        mediaId: ids.media,
      }),
    ).resolves.toMatchObject({ generation: 2, processingRunId: ids.run });

    const reorder = service([
      {
        audit_event_id: ids.audit,
        collection_version: 8,
        inventory_unit_id: ids.inventory,
        outbox_event_id: ids.outbox,
        replayed: false,
      },
    ]);
    await reorder.service.reorder({
      ...command({
        expectedCollectionVersion: 7,
        orderedMediaIds: [ids.media2, ids.media],
      }),
      inventoryUnitId: ids.inventory,
    });
    expect(reorder.invoke.mock.calls[0]?.[0]).toMatchObject({
      functionName: "reorder_inventory_media",
      parameters: {
        p_expected_collection_version: 7,
        p_inventory_unit_id: ids.inventory,
        p_ordered_media_ids: [ids.media2, ids.media],
      },
    });

    const cover = service([
      {
        audit_event_id: ids.audit,
        collection_version: 9,
        cover_media_id: ids.media2,
        inventory_unit_id: ids.inventory,
        outbox_event_id: ids.outbox,
        replayed: false,
      },
    ]);
    await expect(
      cover.service.setCover({
        ...command({ expectedCollectionVersion: 8 }),
        inventoryUnitId: ids.inventory,
        mediaId: ids.media2,
      }),
    ).resolves.toMatchObject({ coverMediaId: ids.media2 });
  });

  it("reads an exact vehicle asset and ordered collection without provider coordinates", async () => {
    const asset = service([{ media: vehicleMediaAsset() }]);
    await expect(
      asset.service.getAsset({
        accessToken: "user-access-token",
        mediaId: ids.media,
        workspaceId: ids.workspace,
      }),
    ).resolves.toMatchObject({
      files: [{ id: ids.file, variant: "thumbnail_320" }],
      id: ids.media,
      mediaVersion: 4,
    });
    expect(asset.invoke).toHaveBeenCalledWith({
      accessToken: "user-access-token",
      functionName: "get_vehicle_media_asset",
      parameters: {
        p_media_id: ids.media,
        p_workspace_id: ids.workspace,
      },
    });

    const list = service([
      {
        collection_version: 8,
        inventory_unit_id: ids.inventory,
        media_items: [
          vehicleMediaAsset(),
          vehicleMediaAsset({
            caption: null,
            id: ids.media2,
            isCover: false,
            sortOrder: 1,
          }),
        ],
      },
    ]);
    const result = await list.service.listInventoryMedia({
      accessToken: "user-access-token",
      inventoryUnitId: ids.inventory,
      workspaceId: ids.workspace,
    });
    expect(result.items.map((item) => item.id)).toEqual([
      ids.media,
      ids.media2,
    ]);
    expect(JSON.stringify(result)).not.toMatch(
      /storage(?:Bucket|ObjectKey|Generation)|serviceRole/iu,
    );
  });

  it("maps caption and archive commands with both optimistic fences", async () => {
    const caption = service([
      {
        audit_event_id: ids.audit,
        caption: "Driver side",
        media_id: ids.media,
        media_version: 5,
        outbox_event_id: ids.outbox,
        replayed: false,
      },
    ]);
    await expect(
      caption.service.updateCaption({
        ...command({ caption: " Driver side ", expectedVersion: 4 }),
        mediaId: ids.media,
      }),
    ).resolves.toMatchObject({ caption: "Driver side", mediaVersion: 5 });
    expect(caption.invoke.mock.calls[0]?.[0]).toMatchObject({
      functionName: "update_vehicle_media_caption",
      parameters: {
        p_caption: "Driver side",
        p_expected_media_version: 4,
        p_media_id: ids.media,
      },
    });

    const archive = service([
      {
        audit_event_id: ids.audit,
        collection_version: 9,
        inventory_unit_id: ids.inventory,
        media_id: ids.media,
        media_status: "archived",
        media_version: 6,
        outbox_event_id: ids.outbox,
        promoted_cover_media_id: ids.media2,
        replayed: false,
      },
    ]);
    await expect(
      archive.service.archive({
        ...command({
          expectedCollectionVersion: 8,
          expectedMediaVersion: 5,
          reason: "Duplicate angle",
        }),
        mediaId: ids.media,
      }),
    ).resolves.toMatchObject({
      collectionVersion: 9,
      mediaStatus: "archived",
      promotedCoverMediaId: ids.media2,
    });
    expect(archive.invoke.mock.calls[0]?.[0]).toMatchObject({
      functionName: "archive_vehicle_media",
      parameters: {
        p_expected_collection_version: 8,
        p_expected_media_version: 5,
        p_media_id: ids.media,
        p_reason: "Duplicate angle",
      },
    });
  });

  it("authorizes only an exact managed file reference", async () => {
    const issue = vi.fn<M2MediaDownloadGrantPort["issue"]>().mockResolvedValue({
      expiresAt: "2026-07-16T12:01:00.000Z",
      url: "https://storage.example.invalid/signed",
    });
    const fixture = service(
      [
        {
          audit_event_id: ids.audit,
          authorization_expires_at: "2026-07-16T12:05:00.000Z",
          authorization_id: ids.authorization,
          byte_size: 800,
          checksum_sha256: "b".repeat(64),
          media_file_id: ids.file,
          media_kind: "vehicle_photo",
          mime_type: "image/webp",
          replayed: false,
        },
      ],
      { issue },
    );
    const result = await fixture.service.authorizeDownload({
      ...command({ expiresInSeconds: 60 }),
      mediaFileId: ids.file,
    });
    expect(result).toMatchObject({
      download: { expiresAt: "2026-07-16T12:01:00.000Z" },
      mediaFileId: ids.file,
      mimeType: "image/webp",
    });
    expect(result).not.toHaveProperty("storageBucket");
    expect(result).not.toHaveProperty("storageGeneration");
    expect(result).not.toHaveProperty("storageObjectKey");
    expect(issue).toHaveBeenCalledWith(
      expect.objectContaining({
        authorizationExpiresAt: "2026-07-16T12:05:00.000Z",
        authorizationId: ids.authorization,
        byteSize: 800,
        checksumSha256: "b".repeat(64),
        expiresInSeconds: 60,
        mediaFileId: ids.file,
        mediaKind: "vehicle_photo",
        mimeType: "image/webp",
        workspaceId: ids.workspace,
      }),
    );
    expect(fixture.invoke.mock.calls[0]?.[0].parameters).toMatchObject({
      p_correlation_id: ids.correlation,
      p_expires_in_seconds: 60,
      p_idempotency_key: "m2-media-command-001",
      p_media_file_id: ids.file,
      p_workspace_id: ids.workspace,
    });
  });

  it("rejects duplicate reorder IDs and browser-supplied completion evidence", async () => {
    const fixture = service([]);
    await expect(
      fixture.service.reorder({
        ...command({
          expectedCollectionVersion: 1,
          orderedMediaIds: [ids.media, ids.media],
        }),
        inventoryUnitId: ids.inventory,
      }),
    ).rejects.toBeInstanceOf(M2MediaValidationError);
    await expect(
      fixture.service.requestUploadVerification({
        ...command({
          checksumSha256: "a".repeat(64),
          uploadSessionId: ids.session,
          verdict: "clean",
        }),
        mediaId: ids.media,
      }),
    ).rejects.toBeInstanceOf(M2MediaValidationError);
    expect(fixture.invoke).not.toHaveBeenCalled();
  });

  it("fails closed on malformed RPC rows and invalid entity identifiers", async () => {
    await expect(
      service([
        { media_id: ids.media, storage_object_key: "leak" },
      ]).service.authorizeDownload({
        ...command({ expiresInSeconds: 60 }),
        mediaFileId: ids.file,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);

    await expect(
      service([
        {
          aggregate_version: 2,
          audit_event_id: ids.audit,
          job_id: ids.job,
          job_status: "queued",
          media_id: ids.media,
          outbox_event_id: ids.outbox,
          replayed: false,
          upload_session_id: crypto.randomUUID(),
        },
      ]).service.requestUploadVerification({
        ...command({ uploadSessionId: ids.session }),
        mediaId: ids.media,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);
    await expect(
      service([]).service.reprocess({
        ...command({ expectedVersion: 1, reason: "Retry" }),
        mediaId: "not-a-uuid",
      }),
    ).rejects.toBeInstanceOf(M2MediaValidationError);
  });

  it("rejects an authorization row for a different media file before signing", async () => {
    const issue = vi.fn<M2MediaDownloadGrantPort["issue"]>();
    const fixture = service(
      [
        {
          audit_event_id: ids.audit,
          authorization_expires_at: "2026-07-16T12:05:00.000Z",
          authorization_id: ids.authorization,
          byte_size: 800,
          checksum_sha256: "b".repeat(64),
          media_file_id: ids.file2,
          media_kind: "vehicle_photo",
          mime_type: "image/webp",
          replayed: false,
        },
      ],
      { issue },
    );

    await expect(
      fixture.service.authorizeDownload({
        ...command({ expiresInSeconds: 60 }),
        mediaFileId: ids.file,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);
    expect(issue).not.toHaveBeenCalled();
  });

  it("rejects echoed media targets that differ from the requested entity", async () => {
    await expect(
      service([
        { media: vehicleMediaAsset({ id: ids.media2 }) },
      ]).service.getAsset({
        accessToken: "user-access-token",
        mediaId: ids.media,
        workspaceId: ids.workspace,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);

    await expect(
      service([
        {
          aggregate_version: 2,
          audit_event_id: ids.audit,
          job_id: ids.job,
          job_status: "queued",
          media_id: ids.media2,
          outbox_event_id: ids.outbox,
          replayed: false,
          upload_session_id: ids.session,
        },
      ]).service.requestUploadVerification({
        ...command({ uploadSessionId: ids.session }),
        mediaId: ids.media,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);

    await expect(
      service([
        {
          aggregate_version: 5,
          audit_event_id: ids.audit,
          generation: 2,
          job_id: ids.job,
          media_id: ids.media2,
          media_status: "quarantined",
          outbox_event_id: ids.outbox,
          processing_run_id: ids.run,
          replayed: false,
        },
      ]).service.reprocess({
        ...command({ expectedVersion: 4, reason: "Retry corrected file" }),
        mediaId: ids.media,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);

    await expect(
      service([
        {
          audit_event_id: ids.audit,
          collection_version: 8,
          inventory_unit_id: ids.inventory2,
          outbox_event_id: ids.outbox,
          replayed: false,
        },
      ]).service.reorder({
        ...command({
          expectedCollectionVersion: 7,
          orderedMediaIds: [ids.media],
        }),
        inventoryUnitId: ids.inventory,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);

    await expect(
      service([
        {
          audit_event_id: ids.audit,
          collection_version: 9,
          cover_media_id: ids.media,
          inventory_unit_id: ids.inventory2,
          outbox_event_id: ids.outbox,
          replayed: false,
        },
      ]).service.setCover({
        ...command({ expectedCollectionVersion: 8 }),
        inventoryUnitId: ids.inventory,
        mediaId: ids.media,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);

    await expect(
      service([
        {
          audit_event_id: ids.audit,
          collection_version: 9,
          cover_media_id: ids.media2,
          inventory_unit_id: ids.inventory,
          outbox_event_id: ids.outbox,
          replayed: false,
        },
      ]).service.setCover({
        ...command({ expectedCollectionVersion: 8 }),
        inventoryUnitId: ids.inventory,
        mediaId: ids.media,
      }),
    ).rejects.toBeInstanceOf(M2MediaRpcContractError);
  });
});
