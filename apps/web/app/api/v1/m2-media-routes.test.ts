import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { POST as setCover } from "./inventory-units/[id]/media/[mediaId]/set-cover/route";
import { GET as listMedia } from "./inventory-units/[id]/media/route";
import { POST as reorder } from "./inventory-units/[id]/media/reorder/route";
import { POST as createUploadIntent } from "./inventory-units/[id]/media/upload-intents/route";
import { POST as requestVerification } from "./media/[id]/complete-upload/route";
import { GET as getMedia, PATCH as updateCaption } from "./media/[id]/route";
import { POST as archiveMedia } from "./media/[id]/archive/route";
import { POST as reprocess } from "./media/[id]/reprocess/route";
import { GET as getUploadStatus } from "./media/[id]/upload-sessions/[uploadSessionId]/route";
import { POST as retryUploadVerification } from "./media/[id]/upload-sessions/[uploadSessionId]/retry/route";
import { POST as createDownloadGrant } from "./media-files/[id]/download-grants/route";

const ids = {
  audit: "11000000-0000-4000-8000-000000000001",
  authorization: "11000000-0000-4000-8000-000000000002",
  correlation: "12000000-0000-4000-8000-000000000001",
  inventory: "13000000-0000-4000-8000-000000000001",
  job: "14000000-0000-4000-8000-000000000001",
  job2: "14000000-0000-4000-8000-000000000002",
  media: "15000000-0000-4000-8000-000000000001",
  media2: "15000000-0000-4000-8000-000000000002",
  outbox: "16000000-0000-4000-8000-000000000001",
  run: "17000000-0000-4000-8000-000000000001",
  session: "18000000-0000-4000-8000-000000000001",
  file: "19000000-0000-4000-8000-000000000001",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;

const publicKey = "sb_publishable_public_project_key_material_0001";
const serviceRole = "server-service-role-must-never-be-used";

function command(path: string, body: unknown): Request {
  return new Request(`http://localhost${path}`, {
    body: JSON.stringify(body),
    headers: {
      Authorization: "Bearer user-header.user-payload.user-signature",
      "Content-Type": "application/json",
      "Idempotency-Key": "m2-media-route-001",
      "X-Correlation-Id": ids.correlation,
      "X-Request-Id": "request-media-route-001",
      "X-Workspace-Id": ids.workspace,
    },
    method: "POST",
  });
}

function query(path: string): Request {
  return new Request(`http://localhost${path}`, {
    headers: {
      Authorization: "Bearer user-header.user-payload.user-signature",
      "X-Correlation-Id": ids.correlation,
      "X-Request-Id": "request-media-query-001",
      "X-Workspace-Id": ids.workspace,
    },
    method: "GET",
  });
}

function vehicleMediaAsset(
  overrides: Readonly<Record<string, unknown>> = {},
): Readonly<Record<string, unknown>> {
  return {
    archivedAt: null,
    caption: "Front view",
    collectionVersion: 4,
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
    mediaVersion: 3,
    processingProfile: {
      checksumSha256: "d".repeat(64),
      id: ids.outbox,
      version: 1,
    },
    sortOrder: 0,
    status: "ready",
    updatedAt: "2026-07-16T12:02:00.000Z",
    ...overrides,
  };
}

function forwarded(
  fetchImplementation: ReturnType<typeof vi.fn<typeof fetch>>,
  index: number,
  functionName: string,
): Record<string, unknown> {
  const [url, init] = fetchImplementation.mock.calls[index] ?? [];
  expect(url).toBe(`http://127.0.0.1:54321/rest/v1/rpc/${functionName}`);
  const headers = new Headers(init?.headers);
  expect(headers.get("apikey")).toBe(publicKey);
  expect(headers.get("authorization")).not.toContain(serviceRole);
  return JSON.parse(String(init?.body)) as Record<string, unknown>;
}

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", publicKey);
  vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", serviceRole);
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("T-MED-003 / T-MED-004 / T-MED-005 / T-STOR-001 M2 authenticated media routes", () => {
  it("maps upload, verification, retry, order, and cover commands to exact RPCs", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
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
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
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
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            aggregate_version: 3,
            audit_event_id: ids.audit,
            generation: 2,
            job_id: ids.job,
            media_id: ids.media,
            media_status: "quarantined",
            outbox_event_id: ids.outbox,
            processing_run_id: ids.run,
            replayed: false,
          },
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            audit_event_id: ids.audit,
            collection_version: 3,
            inventory_unit_id: ids.inventory,
            outbox_event_id: ids.outbox,
            replayed: false,
          },
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            audit_event_id: ids.audit,
            collection_version: 4,
            cover_media_id: ids.media,
            inventory_unit_id: ids.inventory,
            outbox_event_id: ids.outbox,
            replayed: false,
          },
        ]),
      );
    vi.stubGlobal("fetch", fetchImplementation);

    const upload = await createUploadIntent(
      command(`/api/v1/inventory-units/${ids.inventory}/media/upload-intents`, {
        byteSize: 1_024,
        checksumSha256: "a".repeat(64),
        filename: "photo.jpg",
        mimeType: "image/jpeg",
      }),
      { params: Promise.resolve({ id: ids.inventory }) },
    );
    expect(upload.status).toBe(201);

    const verification = await requestVerification(
      command(`/api/v1/media/${ids.media}/complete-upload`, {
        uploadSessionId: ids.session,
      }),
      { params: Promise.resolve({ id: ids.media }) },
    );
    expect(verification.status).toBe(202);

    const retry = await reprocess(
      command(`/api/v1/media/${ids.media}/reprocess`, {
        expectedVersion: 2,
        reason: "Operator retry after provider recovery.",
      }),
      { params: Promise.resolve({ id: ids.media }) },
    );
    expect(retry.status).toBe(202);

    const order = await reorder(
      command(`/api/v1/inventory-units/${ids.inventory}/media/reorder`, {
        expectedCollectionVersion: 2,
        orderedMediaIds: [ids.media, ids.media2],
      }),
      { params: Promise.resolve({ id: ids.inventory }) },
    );
    expect(order.status).toBe(200);

    const cover = await setCover(
      command(
        `/api/v1/inventory-units/${ids.inventory}/media/${ids.media}/set-cover`,
        { expectedCollectionVersion: 3 },
      ),
      { params: Promise.resolve({ id: ids.inventory, mediaId: ids.media }) },
    );
    expect(cover.status).toBe(200);

    expect(
      forwarded(fetchImplementation, 0, "create_vehicle_photo_upload_session"),
    ).toMatchObject({
      p_checksum_sha256: "a".repeat(64),
      p_inventory_unit_id: ids.inventory,
    });
    expect(
      forwarded(
        fetchImplementation,
        1,
        "request_vehicle_photo_upload_verification",
      ),
    ).toMatchObject({ p_upload_session_id: ids.session });
    expect(
      forwarded(fetchImplementation, 2, "reprocess_vehicle_photo"),
    ).toMatchObject({ p_expected_version: 2, p_media_id: ids.media });
    expect(
      forwarded(fetchImplementation, 3, "reorder_inventory_media"),
    ).toMatchObject({
      p_inventory_unit_id: ids.inventory,
      p_ordered_media_ids: [ids.media, ids.media2],
    });
    expect(
      forwarded(fetchImplementation, 4, "set_inventory_media_cover"),
    ).toMatchObject({
      p_inventory_unit_id: ids.inventory,
      p_media_id: ids.media,
    });
  });

  it("rejects an upload intent without a checksum before database traffic", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createUploadIntent(
      command(`/api/v1/inventory-units/${ids.inventory}/media/upload-intents`, {
        byteSize: 1_024,
        filename: "photo.jpg",
        mimeType: "image/jpeg",
      }),
      { params: Promise.resolve({ id: ids.inventory }) },
    );
    expect(response.status).toBe(422);
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it("reads bounded upload failure state and reasons a dead-letter retry", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
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
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            aggregate_version: 3,
            audit_event_id: ids.audit,
            job_id: ids.job2,
            job_status: "queued",
            media_id: ids.media,
            outbox_event_id: ids.outbox,
            replayed: false,
            source_job_id: ids.job,
            upload_session_id: ids.session,
          },
        ]),
      );
    vi.stubGlobal("fetch", fetchImplementation);

    const status = await getUploadStatus(
      query(`/api/v1/media/${ids.media}/upload-sessions/${ids.session}`),
      {
        params: Promise.resolve({
          id: ids.media,
          uploadSessionId: ids.session,
        }),
      },
    );
    expect(status.status).toBe(200);
    const statusBody = await status.json();
    expect(statusBody).toMatchObject({
      data: {
        job: { attemptCount: 6, maximumAttempts: 6 },
        mediaId: ids.media,
        retryable: true,
        status: "dead_letter",
        uploadSessionId: ids.session,
      },
    });
    expect(JSON.stringify(statusBody)).not.toMatch(
      /storage(?:Bucket|ObjectKey|Generation)|provider|detail/iu,
    );

    const retry = await retryUploadVerification(
      command(
        `/api/v1/media/${ids.media}/upload-sessions/${ids.session}/retry`,
        { reason: "Private storage recovered." },
      ),
      {
        params: Promise.resolve({
          id: ids.media,
          uploadSessionId: ids.session,
        }),
      },
    );
    expect(retry.status).toBe(202);
    expect(await retry.json()).toMatchObject({
      data: {
        jobId: ids.job2,
        mediaId: ids.media,
        sourceJobId: ids.job,
        uploadSessionId: ids.session,
      },
    });
    expect(
      forwarded(fetchImplementation, 0, "get_vehicle_photo_upload_status"),
    ).toEqual({
      p_media_id: ids.media,
      p_upload_session_id: ids.session,
      p_workspace_id: ids.workspace,
    });
    expect(
      forwarded(
        fetchImplementation,
        1,
        "retry_vehicle_photo_upload_verification",
      ),
    ).toMatchObject({
      p_media_id: ids.media,
      p_reason: "Private storage recovered.",
      p_upload_session_id: ids.session,
    });
  });

  it("reads, captions, and archives exact vehicle media without exposing storage coordinates", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
          {
            collection_version: 4,
            inventory_unit_id: ids.inventory,
            media_items: [vehicleMediaAsset()],
          },
        ]),
      )
      .mockResolvedValueOnce(Response.json([{ media: vehicleMediaAsset() }]))
      .mockResolvedValueOnce(
        Response.json([
          {
            audit_event_id: ids.audit,
            caption: "Front hero",
            media_id: ids.media,
            media_version: 4,
            outbox_event_id: ids.outbox,
            replayed: false,
          },
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            audit_event_id: ids.audit,
            collection_version: 5,
            inventory_unit_id: ids.inventory,
            media_id: ids.media,
            media_status: "archived",
            media_version: 5,
            outbox_event_id: ids.outbox,
            promoted_cover_media_id: ids.media2,
            replayed: false,
          },
        ]),
      );
    vi.stubGlobal("fetch", fetchImplementation);

    const list = await listMedia(
      query(`/api/v1/inventory-units/${ids.inventory}/media`),
      { params: Promise.resolve({ id: ids.inventory }) },
    );
    expect(list.status).toBe(200);
    expect(JSON.stringify(await list.json())).not.toMatch(
      /storage(?:Bucket|ObjectKey|Generation)|serviceRole/iu,
    );

    const exact = await getMedia(query(`/api/v1/media/${ids.media}`), {
      params: Promise.resolve({ id: ids.media }),
    });
    expect(exact.status).toBe(200);

    const caption = await updateCaption(
      new Request(`http://localhost/api/v1/media/${ids.media}`, {
        body: JSON.stringify({ caption: "Front hero", expectedVersion: 3 }),
        headers: command("/", {}).headers,
        method: "PATCH",
      }),
      { params: Promise.resolve({ id: ids.media }) },
    );
    expect(caption.status).toBe(200);

    const archive = await archiveMedia(
      command(`/api/v1/media/${ids.media}/archive`, {
        expectedCollectionVersion: 4,
        expectedMediaVersion: 4,
        reason: "Duplicate angle",
      }),
      { params: Promise.resolve({ id: ids.media }) },
    );
    expect(archive.status).toBe(200);

    expect(
      forwarded(fetchImplementation, 0, "list_inventory_vehicle_media"),
    ).toEqual({
      p_inventory_unit_id: ids.inventory,
      p_workspace_id: ids.workspace,
    });
    expect(
      forwarded(fetchImplementation, 1, "get_vehicle_media_asset"),
    ).toEqual({ p_media_id: ids.media, p_workspace_id: ids.workspace });
    expect(
      forwarded(fetchImplementation, 2, "update_vehicle_media_caption"),
    ).toMatchObject({ p_expected_media_version: 3, p_media_id: ids.media });
    expect(
      forwarded(fetchImplementation, 3, "archive_vehicle_media"),
    ).toMatchObject({
      p_expected_collection_version: 4,
      p_expected_media_version: 4,
      p_media_id: ids.media,
    });
  });

  it("audits authorization and verifies immutable storage bytes before signing", async () => {
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const authorizationExpiresAt = new Date(Date.now() + 300_000).toISOString();
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new Uint8Array(bytes).buffer,
    );
    const checksum = [...new Uint8Array(digest)]
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
          {
            audit_event_id: ids.audit,
            authorization_expires_at: authorizationExpiresAt,
            authorization_id: ids.authorization,
            byte_size: bytes.byteLength,
            checksum_sha256: checksum,
            media_file_id: ids.file,
            media_kind: "legal_document",
            mime_type: "application/pdf",
            replayed: false,
          },
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            authorization_expires_at: authorizationExpiresAt,
            authorization_id: ids.authorization,
            byte_size: bytes.byteLength,
            checksum_sha256: checksum,
            media_file_id: ids.file,
            media_kind: "legal_document",
            mime_type: "application/pdf",
            signed_url_ttl_seconds: 60,
            storage_bucket: "media-private",
            storage_generation: '"generation-1"',
            storage_object_key: `workspaces/${ids.workspace}/documents/original.pdf`,
            workspace_id: ids.workspace,
          },
        ]),
      )
      .mockResolvedValueOnce(
        new Response(bytes, {
          headers: {
            "Content-Type": "application/pdf",
            ETag: '"generation-1"',
          },
        }),
      )
      .mockResolvedValueOnce(
        Response.json({
          signedURL:
            "/storage/v1/object/sign/media-private/exact?grant=fixture",
        }),
      );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createDownloadGrant(
      command(`/api/v1/media-files/${ids.file}/download-grants`, {
        expiresInSeconds: 60,
      }),
      { params: Promise.resolve({ id: ids.file }) },
    );
    expect(response.status).toBe(200);
    const responseBody = await response.json();
    expect(responseBody).toMatchObject({
      data: {
        auditEventId: ids.audit,
        download: { url: expect.stringContaining("grant=fixture") },
        mediaFileId: ids.file,
        mediaKind: "legal_document",
      },
    });
    expect(responseBody.data).not.toHaveProperty("storageBucket");
    expect(responseBody.data).not.toHaveProperty("storageGeneration");
    expect(responseBody.data).not.toHaveProperty("storageObjectKey");
    expect(
      forwarded(fetchImplementation, 0, "authorize_managed_media_download"),
    ).toMatchObject({
      p_idempotency_key: "m2-media-route-001",
      p_media_file_id: ids.file,
      p_expires_in_seconds: 60,
    });
    expect(fetchImplementation.mock.calls[1]?.[0]).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/load_managed_media_download_authorization",
    );
    expect(
      new Headers(fetchImplementation.mock.calls[1]?.[1]?.headers).get(
        "authorization",
      ),
    ).toBe(`Bearer ${serviceRole}`);
    expect(fetchImplementation.mock.calls[2]?.[1]?.method).toBe("GET");
    expect(fetchImplementation.mock.calls[3]?.[1]?.method).toBe("POST");
  });
});
