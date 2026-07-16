import { MediaPolicyError } from "./errors";
import { VEHICLE_MEDIA_STATUSES, type VehicleMediaStatus } from "./lifecycle";
import {
  deepFreeze,
  requirePositiveSafeInteger,
  requireUuid,
} from "./validation";

export interface MediaCollectionItem {
  readonly mediaId: string;
  readonly status: VehicleMediaStatus;
  readonly sortOrder: number;
  readonly isCover: boolean;
}

export interface MediaCollectionMutationPlan<TUpdate> {
  readonly previousCollectionVersion: number;
  readonly nextCollectionVersion: number;
  readonly updates: readonly TUpdate[];
}

function requireCollectionVersion(
  actualCollectionVersion: number,
  expectedCollectionVersion: number,
): number {
  const actual = requirePositiveSafeInteger(
    actualCollectionVersion,
    "stale_collection_version",
  );
  const expected = requirePositiveSafeInteger(
    expectedCollectionVersion,
    "stale_collection_version",
  );
  if (actual !== expected) {
    throw new MediaPolicyError("stale_collection_version");
  }
  if (actual === Number.MAX_SAFE_INTEGER) {
    throw new MediaPolicyError("stale_collection_version");
  }
  return actual;
}

function activeItems(
  items: readonly MediaCollectionItem[],
): readonly MediaCollectionItem[] {
  return items
    .filter((item) => item.status !== "archived")
    .sort((left, right) => left.sortOrder - right.sortOrder);
}

export function assertMediaCollectionInvariant(
  items: readonly MediaCollectionItem[],
): void {
  const seenIds = new Set<string>();
  const statuses = new Set<string>(VEHICLE_MEDIA_STATUSES);
  for (const item of items) {
    const mediaId = requireUuid(item.mediaId, "invalid_collection");
    if (
      seenIds.has(mediaId) ||
      !statuses.has(item.status) ||
      !Number.isSafeInteger(item.sortOrder) ||
      item.sortOrder < 0 ||
      typeof item.isCover !== "boolean" ||
      (item.status === "archived" && item.isCover)
    ) {
      throw new MediaPolicyError("invalid_collection");
    }
    seenIds.add(mediaId);
  }

  const active = activeItems(items);
  if (
    active.some((item, index) => item.sortOrder !== index) ||
    active.filter((item) => item.isCover).length !== (active.length > 0 ? 1 : 0)
  ) {
    throw new MediaPolicyError("invalid_collection");
  }
}

export function planMediaReorder(input: {
  readonly items: readonly MediaCollectionItem[];
  readonly orderedMediaIds: readonly string[];
  readonly actualCollectionVersion: number;
  readonly expectedCollectionVersion: number;
}): MediaCollectionMutationPlan<
  Readonly<{ mediaId: string; sortOrder: number }>
> {
  assertMediaCollectionInvariant(input.items);
  const version = requireCollectionVersion(
    input.actualCollectionVersion,
    input.expectedCollectionVersion,
  );
  const expectedIds = activeItems(input.items).map((item) =>
    item.mediaId.toLowerCase(),
  );
  const orderedIds = input.orderedMediaIds.map((id) =>
    requireUuid(id, "invalid_media_order"),
  );
  if (
    orderedIds.length !== expectedIds.length ||
    new Set(orderedIds).size !== orderedIds.length ||
    [...orderedIds].sort().join("|") !== [...expectedIds].sort().join("|")
  ) {
    throw new MediaPolicyError("invalid_media_order");
  }

  return deepFreeze({
    previousCollectionVersion: version,
    nextCollectionVersion: version + 1,
    updates: orderedIds.map((mediaId, sortOrder) => ({ mediaId, sortOrder })),
  });
}

export function planSetMediaCover(input: {
  readonly items: readonly MediaCollectionItem[];
  readonly coverMediaId: string;
  readonly actualCollectionVersion: number;
  readonly expectedCollectionVersion: number;
}): MediaCollectionMutationPlan<
  Readonly<{ mediaId: string; isCover: boolean }>
> {
  assertMediaCollectionInvariant(input.items);
  const version = requireCollectionVersion(
    input.actualCollectionVersion,
    input.expectedCollectionVersion,
  );
  const coverMediaId = requireUuid(input.coverMediaId, "invalid_cover");
  const active = activeItems(input.items);
  if (!active.some((item) => item.mediaId.toLowerCase() === coverMediaId)) {
    throw new MediaPolicyError("invalid_cover");
  }

  return deepFreeze({
    previousCollectionVersion: version,
    nextCollectionVersion: version + 1,
    updates: active.map((item) => ({
      mediaId: item.mediaId.toLowerCase(),
      isCover: item.mediaId.toLowerCase() === coverMediaId,
    })),
  });
}

export function planArchiveMediaCollectionItem(input: {
  readonly items: readonly MediaCollectionItem[];
  readonly mediaId: string;
  readonly actualCollectionVersion: number;
  readonly expectedCollectionVersion: number;
}): MediaCollectionMutationPlan<MediaCollectionItem> {
  assertMediaCollectionInvariant(input.items);
  const version = requireCollectionVersion(
    input.actualCollectionVersion,
    input.expectedCollectionVersion,
  );
  const mediaId = requireUuid(input.mediaId, "invalid_collection");
  const target = activeItems(input.items).find(
    (item) => item.mediaId.toLowerCase() === mediaId,
  );
  if (target === undefined) {
    throw new MediaPolicyError("invalid_collection");
  }

  const remaining = activeItems(input.items).filter(
    (item) => item.mediaId.toLowerCase() !== mediaId,
  );
  const nextCoverId = target.isCover
    ? (remaining[0]?.mediaId.toLowerCase() ?? null)
    : (remaining.find((item) => item.isCover)?.mediaId.toLowerCase() ?? null);
  const updates: MediaCollectionItem[] = [
    {
      ...target,
      mediaId,
      status: "archived",
      isCover: false,
    },
    ...remaining.map((item, sortOrder) => ({
      ...item,
      mediaId: item.mediaId.toLowerCase(),
      sortOrder,
      isCover: item.mediaId.toLowerCase() === nextCoverId,
    })),
  ];

  return deepFreeze({
    previousCollectionVersion: version,
    nextCollectionVersion: version + 1,
    updates,
  });
}
