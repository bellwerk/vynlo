import { describe, expect, it } from "vitest";

import {
  assertMediaCollectionInvariant,
  planArchiveMediaCollectionItem,
  planMediaReorder,
  planSetMediaCover,
  type MediaCollectionItem,
} from "./collection";
import { MediaPolicyError } from "./errors";

const MEDIA_A = "10000000-0000-4000-8000-000000000001";
const MEDIA_B = "10000000-0000-4000-8000-000000000002";
const MEDIA_C = "10000000-0000-4000-8000-000000000003";
const MEDIA_D = "10000000-0000-4000-8000-000000000004";

const items: readonly MediaCollectionItem[] = [
  { mediaId: MEDIA_A, status: "ready", sortOrder: 0, isCover: true },
  { mediaId: MEDIA_B, status: "processing", sortOrder: 1, isCover: false },
  { mediaId: MEDIA_C, status: "failed", sortOrder: 2, isCover: false },
];

function expectCode(operation: () => unknown, code: string): void {
  expect(operation).toThrowError(MediaPolicyError);
  try {
    operation();
  } catch (error) {
    expect(error).toMatchObject({ code });
  }
}

describe("M2-MEDIA vehicle-photo collection concurrency", () => {
  it("VYN-MEDIA-001 / T-MED-005 requires one cover and contiguous active order", () => {
    expect(() => assertMediaCollectionInvariant(items)).not.toThrow();
    for (const invalid of [
      items.map((item) => ({ ...item, isCover: false })),
      items.map((item, index) => ({
        ...item,
        isCover: index < 2,
      })),
      items.map((item, index) => ({
        ...item,
        sortOrder: index === 2 ? 4 : item.sortOrder,
      })),
      [
        ...items,
        {
          mediaId: MEDIA_A,
          status: "ready" as const,
          sortOrder: 3,
          isCover: false,
        },
      ],
    ]) {
      expectCode(
        () => assertMediaCollectionInvariant(invalid),
        "invalid_collection",
      );
    }
  });

  it("VYN-MEDIA-001 / T-MED-005 produces a contiguous reorder under expected version", () => {
    const plan = planMediaReorder({
      items,
      orderedMediaIds: [MEDIA_C, MEDIA_A, MEDIA_B],
      actualCollectionVersion: 7,
      expectedCollectionVersion: 7,
    });

    expect(plan).toEqual({
      previousCollectionVersion: 7,
      nextCollectionVersion: 8,
      updates: [
        { mediaId: MEDIA_C, sortOrder: 0 },
        { mediaId: MEDIA_A, sortOrder: 1 },
        { mediaId: MEDIA_B, sortOrder: 2 },
      ],
    });
    expect(Object.isFrozen(plan.updates)).toBe(true);
  });

  it("VYN-MEDIA-001 / T-MED-005 rejects stale, duplicate, missing, and foreign reorder input", () => {
    expectCode(
      () =>
        planMediaReorder({
          items,
          orderedMediaIds: [MEDIA_A, MEDIA_B, MEDIA_C],
          actualCollectionVersion: 7,
          expectedCollectionVersion: 6,
        }),
      "stale_collection_version",
    );
    for (const orderedMediaIds of [
      [MEDIA_A, MEDIA_A, MEDIA_C],
      [MEDIA_A, MEDIA_B],
      [MEDIA_A, MEDIA_B, MEDIA_D],
    ]) {
      expectCode(
        () =>
          planMediaReorder({
            items,
            orderedMediaIds,
            actualCollectionVersion: 7,
            expectedCollectionVersion: 7,
          }),
        "invalid_media_order",
      );
    }
  });

  it("VYN-MEDIA-001 / T-MED-005 changes cover atomically", () => {
    const plan = planSetMediaCover({
      items,
      coverMediaId: MEDIA_C,
      actualCollectionVersion: 7,
      expectedCollectionVersion: 7,
    });
    expect(plan.updates).toEqual([
      { mediaId: MEDIA_A, isCover: false },
      { mediaId: MEDIA_B, isCover: false },
      { mediaId: MEDIA_C, isCover: true },
    ]);
    expectCode(
      () =>
        planSetMediaCover({
          items,
          coverMediaId: MEDIA_D,
          actualCollectionVersion: 7,
          expectedCollectionVersion: 7,
        }),
      "invalid_cover",
    );
  });

  it("VYN-MEDIA-001 / T-MED-005 archives cover, promotes first survivor, and compacts order", () => {
    const plan = planArchiveMediaCollectionItem({
      items,
      mediaId: MEDIA_A,
      actualCollectionVersion: 7,
      expectedCollectionVersion: 7,
    });
    expect(plan.updates).toEqual([
      {
        mediaId: MEDIA_A,
        status: "archived",
        sortOrder: 0,
        isCover: false,
      },
      {
        mediaId: MEDIA_B,
        status: "processing",
        sortOrder: 0,
        isCover: true,
      },
      {
        mediaId: MEDIA_C,
        status: "failed",
        sortOrder: 1,
        isCover: false,
      },
    ]);
  });
});
