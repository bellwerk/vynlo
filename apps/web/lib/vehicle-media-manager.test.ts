import { describe, expect, it } from "vitest";

import {
  moveVehicleMediaIds,
  parseThumbnailGrant,
  parseVehicleMediaCollection,
  selectVehicleThumbnail,
  VehicleMediaResponseError,
} from "./vehicle-media-manager";

const ids = {
  audit: "11000000-0000-4000-8000-000000000001",
  file: "12000000-0000-4000-8000-000000000001",
  inventory: "13000000-0000-4000-8000-000000000001",
  media: "14000000-0000-4000-8000-000000000001",
  media2: "14000000-0000-4000-8000-000000000002",
  profile: "15000000-0000-4000-8000-000000000001",
  run: "16000000-0000-4000-8000-000000000001",
} as const;

function asset(overrides: Readonly<Record<string, unknown>> = {}) {
  return {
    archivedAt: null,
    caption: "Front view",
    collectionVersion: 3,
    createdAt: "2026-07-16T12:00:00.000Z",
    files: [
      {
        byteSize: 800,
        checksumSha256: "a".repeat(64),
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
    mediaVersion: 2,
    processingProfile: {
      checksumSha256: "b".repeat(64),
      id: ids.profile,
      version: 1,
    },
    sortOrder: 0,
    status: "ready",
    updatedAt: "2026-07-16T12:02:00.000Z",
    ...overrides,
  };
}

describe("T-MED-005 / T-STOR-001 vehicle media manager boundary", () => {
  it("parses an ordered exact collection and selects only persisted thumbnails", () => {
    const result = parseVehicleMediaCollection({
      data: {
        collectionVersion: 3,
        inventoryUnitId: ids.inventory,
        items: [
          asset(),
          asset({
            caption: null,
            files: [],
            id: ids.media2,
            isCover: false,
            sortOrder: 1,
          }),
        ],
      },
    });
    expect(selectVehicleThumbnail(result.items[0]!)).toMatchObject({
      id: ids.file,
      variant: "thumbnail_320",
    });
    expect(selectVehicleThumbnail(result.items[1]!)).toBeNull();
    expect(moveVehicleMediaIds(result.items, ids.media, 1)).toEqual([
      ids.media2,
      ids.media,
    ]);
  });

  it("rejects provider coordinates, gaps, and archived assets in an active collection", () => {
    expect(() =>
      parseVehicleMediaCollection({
        data: {
          collectionVersion: 3,
          inventoryUnitId: ids.inventory,
          items: [asset({ storageObjectKey: "must-not-cross" })],
        },
      }),
    ).toThrow(VehicleMediaResponseError);
    expect(() =>
      parseVehicleMediaCollection({
        data: {
          collectionVersion: 3,
          inventoryUnitId: ids.inventory,
          items: [asset({ sortOrder: 1 })],
        },
      }),
    ).toThrow(VehicleMediaResponseError);
    expect(() =>
      parseVehicleMediaCollection({
        data: {
          collectionVersion: 3,
          inventoryUnitId: ids.inventory,
          items: [
            asset({
              archivedAt: "2026-07-16T13:00:00.000Z",
              status: "archived",
            }),
          ],
        },
      }),
    ).toThrow(VehicleMediaResponseError);
  });

  it("accepts only an exact short-lived vehicle thumbnail grant", () => {
    expect(
      parseThumbnailGrant(
        {
          data: {
            auditEventId: ids.audit,
            byteSize: 800,
            checksumSha256: "a".repeat(64),
            download: {
              expiresAt: "2026-07-16T12:05:00.000Z",
              url: "https://storage.example.invalid/signed",
            },
            mediaFileId: ids.file,
            mediaKind: "vehicle_photo",
            mimeType: "image/webp",
            replayed: false,
          },
        },
        ids.file,
      ),
    ).toEqual({
      expiresAt: "2026-07-16T12:05:00.000Z",
      url: "https://storage.example.invalid/signed",
    });
    expect(() =>
      parseThumbnailGrant(
        {
          data: {
            auditEventId: ids.audit,
            byteSize: 800,
            checksumSha256: "a".repeat(64),
            download: {
              expiresAt: "2026-07-16T12:05:00.000Z",
              url: "javascript:alert(1)",
            },
            mediaFileId: ids.file,
            mediaKind: "vehicle_photo",
            mimeType: "image/webp",
            replayed: false,
          },
        },
        ids.file,
      ),
    ).toThrow(VehicleMediaResponseError);
  });
});
