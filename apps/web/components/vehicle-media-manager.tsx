/* eslint-disable @next/next/no-img-element -- exact short-lived media URLs use runtime storage hosts */
"use client";

import { Button } from "@vynlo/ui-web/components/button";
import { Input } from "@vynlo/ui-web/components/input";
import { Textarea } from "@vynlo/ui-web/components/textarea";
import {
  ArrowDown,
  ArrowLeft,
  ArrowUp,
  Check,
  CircleAlert,
  Image as ImageIcon,
  LoaderCircle,
  RefreshCcw,
  RotateCcw,
  Save,
  Star,
  Trash2,
} from "lucide-react";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";

import type { InventoryIntakeCopy } from "../i18n/inventory-intake-messages";
import type { VehicleMediaManagerCopy } from "../i18n/vehicle-media-messages";
import { getBrowserSupabase } from "../lib/supabase-browser";
import {
  moveVehicleMediaIds,
  parseThumbnailGrant,
  parseVehicleMediaCollection,
  selectVehicleThumbnail,
  vehicleMediaIsTransient,
  type VehicleMediaAsset,
  type VehicleMediaCollection,
  type VehicleMediaStatus,
} from "../lib/vehicle-media-manager";
import { OperatorShell, type OperatorWorkspaceOption } from "./operator-shell";
import { VehiclePhotoUpload } from "./vehicle-photo-upload";

interface ThumbnailGrant {
  readonly expiresAt: string;
  readonly fileId: string;
  readonly url: string;
}

type BusyAction = "archive" | "caption" | "cover" | "reorder" | "reprocess";

class MediaManagerRequestError extends Error {
  readonly conflict: boolean;

  constructor(conflict = false) {
    super("Vehicle media request failed.");
    this.name = "MediaManagerRequestError";
    this.conflict = conflict;
  }
}

const PREVIEW_MEDIA_IDS = [
  "00000000-0000-4000-8000-000000000451",
  "00000000-0000-4000-8000-000000000452",
] as const;
const PREVIEW_PROFILE_ID = "00000000-0000-4000-8000-000000000453";
const PREVIEW_WORKSPACE_ID = "00000000-0000-4000-8000-000000000201";
const PREVIEW_WORKSPACE: OperatorWorkspaceOption = Object.freeze({
  id: PREVIEW_WORKSPACE_ID,
  name: "Sample workspace",
});
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

function interpolate(
  template: string,
  values: Readonly<Record<string, string | number>>,
): string {
  return Object.entries(values).reduce(
    (result, [key, value]) => result.replace(`{${key}}`, String(value)),
    template,
  );
}

function previewAsset(
  inventoryUnitId: string,
  id: string,
  sortOrder: number,
): VehicleMediaAsset {
  const timestamp = "2026-07-16T14:00:00.000Z";
  return Object.freeze({
    archivedAt: null,
    caption: sortOrder === 0 ? "Front three-quarter view" : "Driver side",
    collectionVersion: 3,
    createdAt: timestamp,
    files: [],
    id,
    inventoryUnitId,
    isCover: sortOrder === 0,
    mediaVersion: 2,
    processingProfile: Object.freeze({
      checksumSha256: "a".repeat(64),
      id: PREVIEW_PROFILE_ID,
      version: 1,
    }),
    sortOrder,
    status: sortOrder === 0 ? "ready" : "failed",
    updatedAt: timestamp,
  });
}

function previewCollection(inventoryUnitId: string): VehicleMediaCollection {
  return Object.freeze({
    collectionVersion: 3,
    inventoryUnitId,
    items: Object.freeze(
      PREVIEW_MEDIA_IDS.map((id, index) =>
        previewAsset(inventoryUnitId, id, index),
      ),
    ),
  });
}

function statusLabel(
  copy: VehicleMediaManagerCopy,
  status: VehicleMediaStatus,
): string {
  switch (status) {
    case "awaiting_upload":
      return copy.statusAwaitingUpload;
    case "failed":
      return copy.statusFailed;
    case "processing":
      return copy.statusProcessing;
    case "quarantined":
      return copy.statusQuarantined;
    case "ready":
      return copy.statusReady;
  }
}

function updatePreviewCollection(
  collection: VehicleMediaCollection,
  items: readonly VehicleMediaAsset[],
): VehicleMediaCollection {
  const collectionVersion = collection.collectionVersion + 1;
  return Object.freeze({
    collectionVersion,
    inventoryUnitId: collection.inventoryUnitId,
    items: Object.freeze(
      items.map((item, index) =>
        Object.freeze({
          ...item,
          collectionVersion,
          sortOrder: index,
        }),
      ),
    ),
  });
}

export interface VehicleMediaManagerProps {
  readonly copy: VehicleMediaManagerCopy;
  readonly inventoryUnitId: string;
  readonly locale: "en" | "fr";
  readonly previewEnabled: boolean;
  readonly uploadCopy: InventoryIntakeCopy;
  readonly workspaceId: string;
}

export interface VehicleMediaManagerWorkspaceProps extends Omit<
  VehicleMediaManagerProps,
  "workspaceId"
> {
  readonly requestedWorkspaceId?: string;
}

export function VehicleMediaManager({
  copy,
  inventoryUnitId,
  locale,
  previewEnabled,
  uploadCopy,
  workspaceId,
}: Readonly<VehicleMediaManagerProps>) {
  const router = useRouter();
  const dirtyCaptions = useRef(new Set<string>());
  const idempotency = useRef(new Map<string, string>());
  const loadSequence = useRef(0);
  const [archiveReason, setArchiveReason] = useState("");
  const [archiveTargetId, setArchiveTargetId] = useState<string | null>(null);
  const [busy, setBusy] = useState<Readonly<{
    action: BusyAction;
    mediaId: string;
  }> | null>(null);
  const [captionDrafts, setCaptionDrafts] = useState<
    Readonly<Record<string, string>>
  >({});
  const [collection, setCollection] = useState<VehicleMediaCollection | null>(
    null,
  );
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [liveMessage, setLiveMessage] = useState("");
  const [loading, setLoading] = useState(true);
  const [thumbnails, setThumbnails] = useState<
    Readonly<Record<string, ThumbnailGrant>>
  >({});

  const commandKey = useCallback((scope: string, payload: unknown): string => {
    const fingerprint = JSON.stringify(payload);
    const key = `${scope}:${fingerprint}`;
    const previous = idempotency.current.get(key);
    if (previous) return previous;
    const next = crypto.randomUUID();
    idempotency.current.set(key, next);
    return next;
  }, []);

  const accessToken = useCallback(async (): Promise<string> => {
    const session = (await getBrowserSupabase().auth.getSession()).data.session;
    if (!session) {
      router.replace("/login");
      throw new MediaManagerRequestError();
    }
    return session.access_token;
  }, [router]);

  const request = useCallback(
    async (
      path: string,
      options: Readonly<{
        body?: unknown;
        idempotencyKey?: string;
        method: "GET" | "PATCH" | "POST";
        token: string;
      }>,
    ): Promise<unknown> => {
      const headers = new Headers({
        Authorization: `Bearer ${options.token}`,
        "X-Correlation-Id": crypto.randomUUID(),
        "X-Request-Id": crypto.randomUUID(),
        "X-Workspace-Id": workspaceId,
      });
      if (options.body !== undefined) {
        headers.set("Content-Type", "application/json");
      }
      if (options.idempotencyKey) {
        headers.set("Idempotency-Key", options.idempotencyKey);
      }
      const response = await fetch(path, {
        ...(options.body === undefined
          ? {}
          : { body: JSON.stringify(options.body) }),
        cache: "no-store",
        headers,
        method: options.method,
      });
      if (!response.ok) {
        throw new MediaManagerRequestError(response.status === 409);
      }
      return response.json();
    },
    [workspaceId],
  );

  const loadThumbnails = useCallback(
    async (
      nextCollection: VehicleMediaCollection,
      token: string,
      sequence: number,
    ): Promise<void> => {
      const grants = await Promise.all(
        nextCollection.items.map(async (media) => {
          const file = selectVehicleThumbnail(media);
          if (!file) return [media.id, null] as const;
          try {
            const payload = { expiresInSeconds: 120 } as const;
            const value = await request(
              `/api/v1/media-files/${file.id}/download-grants`,
              {
                body: payload,
                idempotencyKey: commandKey(
                  `vehicle-thumbnail:${file.id}`,
                  payload,
                ),
                method: "POST",
                token,
              },
            );
            const grant = parseThumbnailGrant(value, file.id);
            return [
              media.id,
              { ...grant, fileId: file.id } satisfies ThumbnailGrant,
            ] as const;
          } catch {
            return [media.id, null] as const;
          }
        }),
      );
      if (loadSequence.current !== sequence) return;
      setThumbnails(
        Object.freeze(
          Object.fromEntries(
            grants.filter(
              (entry): entry is readonly [string, ThumbnailGrant] =>
                entry[1] !== null,
            ),
          ),
        ),
      );
    },
    [commandKey, request],
  );

  const load = useCallback(async (): Promise<void> => {
    const sequence = ++loadSequence.current;
    setLoading(collection === null);
    try {
      if (previewEnabled) {
        const next = collection ?? previewCollection(inventoryUnitId);
        if (loadSequence.current !== sequence) return;
        setCollection(next);
        setCaptionDrafts((current) => {
          const drafts = { ...current };
          for (const item of next.items) {
            if (!dirtyCaptions.current.has(item.id)) {
              drafts[item.id] = item.caption ?? "";
            }
          }
          return Object.freeze(drafts);
        });
        setErrorMessage(null);
        return;
      }
      const token = await accessToken();
      const value = await request(
        `/api/v1/inventory-units/${inventoryUnitId}/media`,
        { method: "GET", token },
      );
      const next = parseVehicleMediaCollection(value);
      if (
        next.inventoryUnitId !== inventoryUnitId ||
        loadSequence.current !== sequence
      ) {
        throw new MediaManagerRequestError();
      }
      setCollection(next);
      setCaptionDrafts((current) => {
        const drafts: Record<string, string> = {};
        for (const item of next.items) {
          drafts[item.id] = dirtyCaptions.current.has(item.id)
            ? (current[item.id] ?? item.caption ?? "")
            : (item.caption ?? "");
        }
        return Object.freeze(drafts);
      });
      setErrorMessage(null);
      await loadThumbnails(next, token, sequence);
    } catch {
      if (loadSequence.current === sequence) setErrorMessage(copy.loadError);
    } finally {
      if (loadSequence.current === sequence) setLoading(false);
    }
  }, [
    accessToken,
    collection,
    copy.loadError,
    inventoryUnitId,
    loadThumbnails,
    previewEnabled,
    request,
  ]);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => {
      window.clearTimeout(timer);
      loadSequence.current += 1;
    };
    // Initial load is intentionally keyed to the exact workspace and inventory.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [inventoryUnitId, workspaceId]);

  useEffect(() => {
    if (
      !collection?.items.some((item) => vehicleMediaIsTransient(item.status))
    ) {
      return;
    }
    const timer = window.setTimeout(
      () => {
        if (previewEnabled) {
          setCollection((current) =>
            current
              ? Object.freeze({
                  ...current,
                  items: Object.freeze(
                    current.items.map((item) =>
                      vehicleMediaIsTransient(item.status)
                        ? Object.freeze({ ...item, status: "ready" as const })
                        : item,
                    ),
                  ),
                })
              : current,
          );
        } else {
          void load();
        }
      },
      previewEnabled ? 1_000 : 3_000,
    );
    return () => window.clearTimeout(timer);
  }, [collection, load, previewEnabled]);

  async function runCommand(
    mediaId: string,
    action: BusyAction,
    path: string,
    method: "PATCH" | "POST",
    payload: unknown,
    previewMutation: (
      current: VehicleMediaCollection,
    ) => VehicleMediaCollection,
    pendingMessage: string,
  ): Promise<boolean> {
    setBusy({ action, mediaId });
    setErrorMessage(null);
    setLiveMessage(pendingMessage);
    try {
      if (previewEnabled) {
        setCollection((current) =>
          current ? previewMutation(current) : current,
        );
      } else {
        const token = await accessToken();
        await request(path, {
          body: payload,
          idempotencyKey: commandKey(`${action}:${mediaId}`, payload),
          method,
          token,
        });
        await load();
      }
      setLiveMessage(copy.savedStatus);
      return true;
    } catch (error) {
      const conflict =
        error instanceof MediaManagerRequestError && error.conflict;
      if (conflict) await load();
      setErrorMessage(conflict ? copy.conflictError : copy.genericError);
      setLiveMessage("");
      return false;
    } finally {
      setBusy(null);
    }
  }

  async function saveCaption(
    event: FormEvent<HTMLFormElement>,
    media: VehicleMediaAsset,
  ): Promise<void> {
    event.preventDefault();
    const caption = captionDrafts[media.id]?.trim() || null;
    const payload = { caption, expectedVersion: media.mediaVersion } as const;
    const saved = await runCommand(
      media.id,
      "caption",
      `/api/v1/media/${media.id}`,
      "PATCH",
      payload,
      (current) =>
        Object.freeze({
          ...current,
          items: Object.freeze(
            current.items.map((item) =>
              item.id === media.id
                ? Object.freeze({
                    ...item,
                    caption,
                    mediaVersion: item.mediaVersion + 1,
                  })
                : item,
            ),
          ),
        }),
      copy.savingStatus,
    );
    if (saved) dirtyCaptions.current.delete(media.id);
  }

  async function move(media: VehicleMediaAsset, direction: -1 | 1) {
    if (!collection) return;
    const orderedMediaIds = moveVehicleMediaIds(
      collection.items,
      media.id,
      direction,
    );
    const payload = {
      expectedCollectionVersion: collection.collectionVersion,
      orderedMediaIds,
    } as const;
    await runCommand(
      media.id,
      "reorder",
      `/api/v1/inventory-units/${inventoryUnitId}/media/reorder`,
      "POST",
      payload,
      (current) => {
        const byId = new Map(current.items.map((item) => [item.id, item]));
        return updatePreviewCollection(
          current,
          orderedMediaIds.map((id) => byId.get(id)!),
        );
      },
      copy.movingStatus,
    );
  }

  async function setCover(media: VehicleMediaAsset) {
    if (!collection) return;
    const payload = {
      expectedCollectionVersion: collection.collectionVersion,
    } as const;
    await runCommand(
      media.id,
      "cover",
      `/api/v1/inventory-units/${inventoryUnitId}/media/${media.id}/set-cover`,
      "POST",
      payload,
      (current) =>
        updatePreviewCollection(
          current,
          current.items.map((item) =>
            Object.freeze({ ...item, isCover: item.id === media.id }),
          ),
        ),
      copy.settingCoverStatus,
    );
  }

  async function reprocess(media: VehicleMediaAsset) {
    const payload = {
      expectedVersion: media.mediaVersion,
      reason: copy.reprocessReason,
    } as const;
    await runCommand(
      media.id,
      "reprocess",
      `/api/v1/media/${media.id}/reprocess`,
      "POST",
      payload,
      (current) =>
        Object.freeze({
          ...current,
          items: Object.freeze(
            current.items.map((item) =>
              item.id === media.id
                ? Object.freeze({
                    ...item,
                    mediaVersion: item.mediaVersion + 1,
                    status: "processing" as const,
                  })
                : item,
            ),
          ),
        }),
      copy.reprocessingStatus,
    );
  }

  async function archive(media: VehicleMediaAsset) {
    if (!collection || !archiveReason.trim()) return;
    const payload = {
      expectedCollectionVersion: collection.collectionVersion,
      expectedMediaVersion: media.mediaVersion,
      reason: archiveReason.trim(),
    } as const;
    const archived = await runCommand(
      media.id,
      "archive",
      `/api/v1/media/${media.id}/archive`,
      "POST",
      payload,
      (current) => {
        const remaining = current.items.filter((item) => item.id !== media.id);
        const hasCover = remaining.some((item) => item.isCover);
        return updatePreviewCollection(
          current,
          remaining.map((item, index) =>
            Object.freeze({
              ...item,
              isCover: hasCover ? item.isCover : index === 0,
            }),
          ),
        );
      },
      copy.archivingStatus,
    );
    if (archived) {
      setArchiveTargetId(null);
      setArchiveReason("");
    }
  }

  const items = collection?.items ?? [];
  const inventoryQuery = previewEnabled
    ? "?preview=inventory"
    : `?workspace=${encodeURIComponent(workspaceId)}`;

  return (
    <div
      aria-label={copy.heading}
      className="vehicle-media-manager"
      data-preview={previewEnabled}
    >
      <header className="vehicle-media-manager__header">
        <a
          className="vehicle-media-manager__back"
          href={`/inventory/${inventoryUnitId}${inventoryQuery}`}
        >
          <ArrowLeft aria-hidden="true" size={17} />
          {copy.backAction}
        </a>
        <div className="vehicle-media-manager__summary">
          <strong>
            {interpolate(copy.countLabel, { count: items.length })}
          </strong>
          <Button
            disabled={loading || busy !== null}
            onClick={() => void load()}
            type="button"
            variant="outline"
          >
            <RefreshCcw aria-hidden="true" size={16} />
            {copy.refreshAction}
          </Button>
        </div>
      </header>

      <p aria-live="polite" className="vehicle-media-manager__live">
        {liveMessage}
      </p>

      {errorMessage ? (
        <div className="vehicle-media-manager__error" role="alert">
          <CircleAlert aria-hidden="true" size={20} />
          <p>{errorMessage}</p>
          <Button onClick={() => void load()} type="button" variant="outline">
            {copy.retryAction}
          </Button>
        </div>
      ) : null}

      {loading && !collection ? (
        <div className="vehicle-media-manager__loading" role="status">
          <LoaderCircle aria-hidden="true" size={21} />
          {copy.loading}
        </div>
      ) : null}

      {!loading && collection && items.length === 0 ? (
        <div className="vehicle-media-manager__empty">
          <ImageIcon aria-hidden="true" size={34} strokeWidth={1.4} />
          <div>
            <h2>{copy.emptyHeading}</h2>
            <p>{copy.emptyDescription}</p>
          </div>
        </div>
      ) : null}

      {items.length > 0 ? (
        <ol aria-label={copy.heading} className="vehicle-media-manager__list">
          {items.map((media, index) => {
            const thumbnail = thumbnails[media.id];
            const itemBusy = busy?.mediaId === media.id;
            const label = interpolate(copy.photoLabel, {
              position: index + 1,
            });
            const captionSuffix = media.caption ? ` · ${media.caption}` : "";
            return (
              <li key={media.id}>
                <article
                  aria-label={label}
                  className="vehicle-media-manager__item"
                >
                  <div className="vehicle-media-manager__visual">
                    {thumbnail ? (
                      <img
                        alt={interpolate(copy.thumbnailAlt, {
                          caption: captionSuffix,
                          position: index + 1,
                        })}
                        decoding="async"
                        height={320}
                        onError={() =>
                          setThumbnails((current) => {
                            const next = { ...current };
                            delete next[media.id];
                            return Object.freeze(next);
                          })
                        }
                        src={thumbnail.url}
                        width={320}
                      />
                    ) : (
                      <div className="vehicle-media-manager__placeholder">
                        <span aria-hidden="true">
                          {String(index + 1).padStart(2, "0")}
                        </span>
                        <p>{copy.thumbnailUnavailable}</p>
                      </div>
                    )}
                    {media.isCover ? (
                      <strong className="vehicle-media-manager__cover">
                        <Star
                          aria-hidden="true"
                          fill="currentColor"
                          size={14}
                        />
                        {copy.coverLabel}
                      </strong>
                    ) : null}
                  </div>

                  <div className="vehicle-media-manager__details">
                    <header>
                      <div>
                        <span>{label}</span>
                        <strong data-status={media.status}>
                          {vehicleMediaIsTransient(media.status) ? (
                            <LoaderCircle aria-hidden="true" size={14} />
                          ) : media.status === "failed" ? (
                            <CircleAlert aria-hidden="true" size={14} />
                          ) : (
                            <Check aria-hidden="true" size={14} />
                          )}
                          {statusLabel(copy, media.status)}
                        </strong>
                      </div>
                      <div className="vehicle-media-manager__order">
                        <Button
                          aria-label={`${copy.moveUpAction}: ${label}`}
                          disabled={itemBusy || busy !== null || index === 0}
                          onClick={() => void move(media, -1)}
                          title={copy.moveUpAction}
                          type="button"
                          variant="outline"
                        >
                          <ArrowUp aria-hidden="true" size={17} />
                        </Button>
                        <Button
                          aria-label={`${copy.moveDownAction}: ${label}`}
                          disabled={
                            itemBusy ||
                            busy !== null ||
                            index === items.length - 1
                          }
                          onClick={() => void move(media, 1)}
                          title={copy.moveDownAction}
                          type="button"
                          variant="outline"
                        >
                          <ArrowDown aria-hidden="true" size={17} />
                        </Button>
                      </div>
                    </header>

                    {vehicleMediaIsTransient(media.status) ? (
                      <p className="vehicle-media-manager__hint" role="status">
                        {copy.transientHint}
                      </p>
                    ) : null}
                    {media.status === "failed" ? (
                      <p className="vehicle-media-manager__hint">
                        {copy.failedHint}
                      </p>
                    ) : null}

                    <form
                      className="vehicle-media-manager__caption"
                      onSubmit={(event) => void saveCaption(event, media)}
                    >
                      <label>
                        <span>{copy.captionLabel}</span>
                        <Input
                          disabled={itemBusy}
                          maxLength={500}
                          onChange={(event) => {
                            dirtyCaptions.current.add(media.id);
                            setCaptionDrafts((current) =>
                              Object.freeze({
                                ...current,
                                [media.id]: event.target.value,
                              }),
                            );
                          }}
                          placeholder={copy.captionPlaceholder}
                          value={captionDrafts[media.id] ?? ""}
                        />
                      </label>
                      <Button
                        disabled={itemBusy || busy !== null}
                        type="submit"
                        variant="outline"
                      >
                        {busy?.action === "caption" && itemBusy ? (
                          <LoaderCircle aria-hidden="true" size={16} />
                        ) : (
                          <Save aria-hidden="true" size={16} />
                        )}
                        {copy.saveCaptionAction}
                      </Button>
                    </form>

                    <div className="vehicle-media-manager__actions">
                      {!media.isCover ? (
                        <Button
                          disabled={itemBusy || busy !== null}
                          onClick={() => void setCover(media)}
                          type="button"
                          variant="outline"
                        >
                          <Star aria-hidden="true" size={16} />
                          {copy.coverAction}
                        </Button>
                      ) : null}
                      {media.status === "failed" ? (
                        <Button
                          disabled={itemBusy || busy !== null}
                          onClick={() => void reprocess(media)}
                          type="button"
                          variant="outline"
                        >
                          <RotateCcw aria-hidden="true" size={16} />
                          {copy.reprocessAction}
                        </Button>
                      ) : null}
                      <Button
                        disabled={itemBusy || busy !== null}
                        onClick={() => {
                          setArchiveReason("");
                          setArchiveTargetId(media.id);
                        }}
                        type="button"
                        variant="outline"
                      >
                        <Trash2 aria-hidden="true" size={16} />
                        {copy.archiveAction}
                      </Button>
                    </div>

                    {archiveTargetId === media.id ? (
                      <div
                        aria-labelledby={`archive-${media.id}`}
                        className="vehicle-media-manager__archive"
                      >
                        <h3 id={`archive-${media.id}`}>
                          {copy.archiveHeading}
                        </h3>
                        <label>
                          <span>{copy.archiveReasonLabel}</span>
                          <Textarea
                            maxLength={1_000}
                            onChange={(event) =>
                              setArchiveReason(event.target.value)
                            }
                            placeholder={copy.archiveReasonPlaceholder}
                            value={archiveReason}
                          />
                        </label>
                        <div>
                          <Button
                            disabled={!archiveReason.trim() || itemBusy}
                            onClick={() => void archive(media)}
                            type="button"
                          >
                            {busy?.action === "archive" && itemBusy ? (
                              <LoaderCircle aria-hidden="true" size={16} />
                            ) : (
                              <Trash2 aria-hidden="true" size={16} />
                            )}
                            {copy.archiveConfirm}
                          </Button>
                          <Button
                            disabled={itemBusy}
                            onClick={() => setArchiveTargetId(null)}
                            type="button"
                            variant="outline"
                          >
                            {copy.archiveCancel}
                          </Button>
                        </div>
                      </div>
                    ) : null}
                  </div>
                </article>
              </li>
            );
          })}
        </ol>
      ) : null}

      <div className="vehicle-media-manager__upload">
        <VehiclePhotoUpload
          copy={uploadCopy}
          description={copy.addHint}
          heading={copy.addHeading}
          inventoryUnitId={inventoryUnitId}
          locale={locale}
          onVerificationQueued={(receipt) => {
            if (previewEnabled) {
              setCollection((current) => {
                if (
                  !current ||
                  current.items.some((item) => item.id === receipt.mediaId)
                ) {
                  return current;
                }
                const next = Object.freeze({
                  ...previewAsset(
                    inventoryUnitId,
                    receipt.mediaId,
                    current.items.length,
                  ),
                  caption: null,
                  collectionVersion: current.collectionVersion + 1,
                  isCover: current.items.length === 0,
                  status: "quarantined" as const,
                });
                return updatePreviewCollection(current, [
                  ...current.items,
                  next,
                ]);
              });
            } else {
              void load();
            }
          }}
          previewEnabled={previewEnabled}
          workspaceId={workspaceId}
        />
      </div>
    </div>
  );
}

export function VehicleMediaManagerWorkspace({
  copy,
  inventoryUnitId,
  locale,
  previewEnabled,
  requestedWorkspaceId,
  uploadCopy,
}: Readonly<VehicleMediaManagerWorkspaceProps>) {
  const router = useRouter();
  const [workspaceId, setWorkspaceId] = useState<string | null>(
    previewEnabled ? PREVIEW_WORKSPACE_ID : null,
  );
  const [workspaces, setWorkspaces] = useState<
    readonly OperatorWorkspaceOption[]
  >(previewEnabled ? [PREVIEW_WORKSPACE] : []);
  const [resolutionFailed, setResolutionFailed] = useState(false);

  useEffect(() => {
    if (previewEnabled) {
      return;
    }
    let active = true;
    async function resolveWorkspace(): Promise<void> {
      try {
        const client = getBrowserSupabase();
        const session = (await client.auth.getSession()).data.session;
        if (!session) {
          router.replace("/login");
          return;
        }
        const memberships = await client
          .from("workspace_memberships")
          .select("id,workspaces!inner(id,name)")
          .eq("user_id", session.user.id)
          .eq("status", "active");
        if (memberships.error || !Array.isArray(memberships.data)) {
          throw new MediaManagerRequestError();
        }
        const authorizedWorkspaces = memberships.data.flatMap((membership) => {
          if (typeof membership !== "object" || membership === null) return [];
          const relation = (membership as Record<string, unknown>).workspaces;
          const workspace = Array.isArray(relation) ? relation[0] : relation;
          if (typeof workspace !== "object" || workspace === null) return [];
          const id = (workspace as Record<string, unknown>).id;
          const name = (workspace as Record<string, unknown>).name;
          return typeof id === "string" &&
            UUID_PATTERN.test(id) &&
            typeof name === "string" &&
            name.trim()
            ? [{ id: id.toLowerCase(), name: name.trim() }]
            : [];
        });
        const requested =
          typeof requestedWorkspaceId === "string" &&
          UUID_PATTERN.test(requestedWorkspaceId)
            ? requestedWorkspaceId.toLowerCase()
            : null;
        const resolved =
          requested &&
          authorizedWorkspaces.some((workspace) => workspace.id === requested)
            ? requested
            : authorizedWorkspaces[0]?.id;
        if (!resolved) throw new MediaManagerRequestError();
        if (active) {
          setWorkspaces(authorizedWorkspaces);
          setWorkspaceId(resolved);
          setResolutionFailed(false);
        }
      } catch {
        if (active) setResolutionFailed(true);
      }
    }
    void resolveWorkspace();
    return () => {
      active = false;
    };
  }, [previewEnabled, requestedWorkspaceId, router]);

  function chooseWorkspace(nextWorkspaceId: string): void {
    if (
      previewEnabled ||
      !workspaces.some((workspace) => workspace.id === nextWorkspaceId)
    ) {
      return;
    }
    setResolutionFailed(false);
    setWorkspaceId(nextWorkspaceId);
    router.replace(
      `/inventory/${inventoryUnitId}/media?workspace=${encodeURIComponent(nextWorkspaceId)}`,
    );
  }

  const shellWorkspaces =
    workspaces.length > 0
      ? workspaces
      : [{ id: "", name: uploadCopy.workspaceLoading }];
  const content = resolutionFailed ? (
    <div className="vehicle-media-manager">
      <div className="vehicle-media-manager__error" role="alert">
        <CircleAlert aria-hidden="true" size={20} />
        <p>{copy.loadError}</p>
      </div>
    </div>
  ) : !workspaceId ? (
    <div className="vehicle-media-manager">
      <div className="vehicle-media-manager__loading" role="status">
        <LoaderCircle aria-hidden="true" size={21} />
        {copy.loading}
      </div>
    </div>
  ) : (
    <VehicleMediaManager
      copy={copy}
      inventoryUnitId={inventoryUnitId}
      key={workspaceId}
      locale={locale}
      previewEnabled={previewEnabled}
      uploadCopy={uploadCopy}
      workspaceId={workspaceId}
    />
  );

  return (
    <OperatorShell
      attentionCount={resolutionFailed ? 1 : 0}
      contextLabel={
        previewEnabled ? uploadCopy.developmentPreview : copy.eyebrow
      }
      copy={{
        appName: "Vynlo",
        attention: copy.statusFailed,
        environment: copy.eyebrow,
        localeLabel: uploadCopy.localeLabel,
        localeNames: uploadCopy.localeNames,
        navigationLabel: `${uploadCopy.navigationLabel} · Vynlo`,
        skipToContent: copy.skipToContent,
        workspaceLabel: uploadCopy.workspaceLabel,
      }}
      current="inventory"
      locale={locale}
      mainId="vehicle-media-main"
      onWorkspaceChange={chooseWorkspace}
      previewMode={previewEnabled ? "inventory" : null}
      selectedWorkspaceId={workspaceId ?? ""}
      summary={copy.description}
      title={copy.heading}
      workspaces={shellWorkspaces}
    >
      {content}
    </OperatorShell>
  );
}
