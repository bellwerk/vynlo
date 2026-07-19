"use client";

import { Button } from "@vynlo/ui-web/components/button";
import { Input } from "@vynlo/ui-web/components/input";
import { Textarea } from "@vynlo/ui-web/components/textarea";
import {
  Check,
  CircleAlert,
  FileImage,
  Hash,
  LoaderCircle,
  RotateCcw,
  ShieldCheck,
  Upload,
} from "lucide-react";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
  type FormEvent,
} from "react";

import {
  vehiclePhotoJobStatusLabel,
  type InventoryIntakeCopy,
} from "../i18n/inventory-intake-messages";
import {
  getBrowserSupabase,
  parsePublicSupabaseConfig,
} from "../lib/supabase-browser";
import {
  clearVehiclePhotoCommandKey,
  isVehiclePhotoUploadIntentExpired,
  parseVehiclePhotoUploadIntent,
  parseVehiclePhotoVerificationReceipt,
  parseVehiclePhotoVerificationStatus,
  sha256Hex,
  validateVehiclePhotoFile,
  VEHICLE_PHOTO_ACCEPT,
  vehiclePhotoCommandKey,
  vehiclePhotoProjectedJobStatus,
  vehiclePhotoReceiptStatus,
  vehiclePhotoStatusMessageKey,
  vehiclePhotoStatusPollDelay,
  vehiclePhotoStatusShouldPoll,
  vehiclePhotoStorageUrl,
  type VehiclePhotoMimeType,
  type VehiclePhotoProjectedStatus,
  type VehiclePhotoUploadIntent,
  type VehiclePhotoValidationErrorCode,
  type VehiclePhotoVerificationReceipt,
  type VehiclePhotoVerificationStatus,
} from "../lib/vehicle-photo-upload";

type UploadPhase =
  | "error"
  | "hashing"
  | "idle"
  | "requesting_intent"
  | "uploading"
  | "verification_queued"
  | "verifying";

interface UploadPipeline {
  checksumSha256: string | null;
  file: File;
  intent: VehiclePhotoUploadIntent | null;
  mimeType: VehiclePhotoMimeType;
  uploaded: boolean;
  uploadAttempts: number;
}

const PREVIEW_MEDIA_ID = "00000000-0000-4000-8000-000000000401";
const PREVIEW_SESSION_ID = "00000000-0000-4000-8000-000000000402";
const PREVIEW_JOB_ID = "00000000-0000-4000-8000-000000000403";

class PhotoUploadError extends Error {
  readonly code: "intent_expired" | "request_failed" | "upload_failed";

  constructor(code: PhotoUploadError["code"]) {
    super(code);
    this.name = "PhotoUploadError";
    this.code = code;
  }
}

function interpolate(
  template: string,
  values: Readonly<Record<string, string | number>>,
): string {
  return Object.entries(values).reduce(
    (result, [key, value]) => result.replace(`{${key}}`, String(value)),
    template,
  );
}

function validationMessage(
  copy: InventoryIntakeCopy,
  code: VehiclePhotoValidationErrorCode,
): string {
  switch (code) {
    case "file_empty":
      return copy.photoEmptyError;
    case "file_too_large":
      return copy.photoSizeError;
    case "unsupported_file_type":
      return copy.photoTypeError;
  }
}

function formatBytes(bytes: number, locale: "en" | "fr"): string {
  return new Intl.NumberFormat(locale, {
    maximumFractionDigits: 1,
    style: "unit",
    unit: "megabyte",
    unitDisplay: "short",
  }).format(bytes / 1_000_000);
}

function stageState(
  stage: "hash" | "upload" | "verification",
  phase: UploadPhase,
  checksumReady: boolean,
  uploadComplete: boolean,
  verificationStatus: VehiclePhotoProjectedStatus | null,
): "complete" | "current" | "waiting" {
  if (stage === "hash") {
    if (phase === "hashing") return "current";
    return checksumReady ? "complete" : "waiting";
  }
  if (stage === "upload") {
    if (phase === "requesting_intent" || phase === "uploading") {
      return "current";
    }
    return uploadComplete ? "complete" : "waiting";
  }
  if (verificationStatus === "completed") return "complete";
  if (
    phase === "verifying" ||
    (phase === "verification_queued" &&
      verificationStatus !== "dead_letter" &&
      verificationStatus !== "rejected")
  ) {
    return "current";
  }
  return "waiting";
}

async function wait(milliseconds: number): Promise<void> {
  await new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

export function VehiclePhotoUpload({
  copy,
  description,
  heading,
  inventoryUnitId,
  locale,
  onVerificationQueued,
  previewEnabled,
  workspaceId,
}: Readonly<{
  copy: InventoryIntakeCopy;
  description?: string;
  heading?: string;
  inventoryUnitId: string;
  locale: "en" | "fr";
  onVerificationQueued?: (receipt: VehiclePhotoVerificationReceipt) => void;
  previewEnabled: boolean;
  workspaceId: string;
}>) {
  const router = useRouter();
  const headingId = useId();
  const hintId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const retryReasonId = useId();
  const retryReasonErrorId = useId();
  const retryReasonRef = useRef<HTMLTextAreaElement>(null);
  const idempotency = useRef(new Map<string, string>());
  const operation = useRef(0);
  const pipeline = useRef<UploadPipeline | null>(null);
  const xhr = useRef<XMLHttpRequest | null>(null);
  const [checksum, setChecksum] = useState<string | null>(null);
  const [canRetry, setCanRetry] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [file, setFile] = useState<File | null>(null);
  const [phase, setPhase] = useState<UploadPhase>("idle");
  const [progress, setProgress] = useState(0);
  const [receipt, setReceipt] =
    useState<VehiclePhotoVerificationReceipt | null>(null);
  const [retryingVerification, setRetryingVerification] = useState(false);
  const [retryReason, setRetryReason] = useState("");
  const [retryReasonError, setRetryReasonError] = useState<string | null>(null);
  const [statusChecking, setStatusChecking] = useState(false);
  const [statusRefreshFailed, setStatusRefreshFailed] = useState(false);
  const [uploadComplete, setUploadComplete] = useState(false);
  const [verificationStatus, setVerificationStatus] =
    useState<VehiclePhotoVerificationStatus | null>(null);

  const busy = [
    "hashing",
    "requesting_intent",
    "uploading",
    "verifying",
  ].includes(phase);

  useEffect(
    () => () => {
      operation.current += 1;
      xhr.current?.abort();
    },
    [],
  );

  function commandKey(scope: string, payload: unknown): string {
    return vehiclePhotoCommandKey(idempotency.current, scope, payload);
  }

  const accessToken = useCallback(async (): Promise<string> => {
    const session = (await getBrowserSupabase().auth.getSession()).data.session;
    if (!session) {
      router.replace("/login");
      throw new PhotoUploadError("request_failed");
    }
    return session.access_token;
  }, [router]);

  const command = useCallback(
    async (
      path: string,
      payload: unknown,
      idempotencyKey: string,
    ): Promise<unknown> => {
      const response = await fetch(path, {
        body: JSON.stringify(payload),
        headers: {
          Authorization: `Bearer ${await accessToken()}`,
          "Content-Type": "application/json",
          "Idempotency-Key": idempotencyKey,
          "X-Correlation-Id": crypto.randomUUID(),
          "X-Request-Id": crypto.randomUUID(),
          "X-Workspace-Id": workspaceId,
        },
        method: "POST",
      });
      if (!response.ok) throw new PhotoUploadError("request_failed");
      return response.json();
    },
    [accessToken, workspaceId],
  );

  useEffect(() => {
    if (receipt === null || previewEnabled) return;

    let active = true;
    let timeoutId: number | null = null;
    const controller = new AbortController();

    const checkStatus = async (attempt: number): Promise<void> => {
      if (!active) return;
      setStatusChecking(true);
      try {
        const response = await fetch(
          `/api/v1/media/${receipt.mediaId}/upload-sessions/${receipt.uploadSessionId}`,
          {
            cache: "no-store",
            headers: {
              Authorization: `Bearer ${await accessToken()}`,
              "X-Workspace-Id": workspaceId,
            },
            method: "GET",
            signal: controller.signal,
          },
        );
        if (!response.ok) throw new PhotoUploadError("request_failed");
        const nextStatus = parseVehiclePhotoVerificationStatus(
          await response.json(),
        );
        if (
          nextStatus.mediaId !== receipt.mediaId ||
          nextStatus.uploadSessionId !== receipt.uploadSessionId
        ) {
          throw new PhotoUploadError("request_failed");
        }
        if (!active) return;
        setVerificationStatus(nextStatus);
        setStatusRefreshFailed(false);
        if (vehiclePhotoStatusShouldPoll(nextStatus.status)) {
          timeoutId = window.setTimeout(
            () => void checkStatus(attempt + 1),
            vehiclePhotoStatusPollDelay(attempt),
          );
        }
      } catch {
        if (!active || controller.signal.aborted) return;
        setStatusRefreshFailed(true);
        timeoutId = window.setTimeout(
          () => void checkStatus(attempt + 1),
          vehiclePhotoStatusPollDelay(attempt),
        );
      } finally {
        if (active) setStatusChecking(false);
      }
    };

    void checkStatus(0);
    return () => {
      active = false;
      controller.abort();
      if (timeoutId !== null) window.clearTimeout(timeoutId);
    };
  }, [accessToken, previewEnabled, receipt, workspaceId]);

  async function uploadObject(
    current: UploadPipeline,
    intent: VehiclePhotoUploadIntent,
    operationId: number,
  ): Promise<void> {
    if (isVehiclePhotoUploadIntentExpired(intent)) {
      throw new PhotoUploadError("intent_expired");
    }
    if (previewEnabled) {
      current.uploadAttempts += 1;
      for (const value of [16, 43, 72, 100]) {
        await wait(45);
        if (operation.current !== operationId) return;
        setProgress(value);
        if (
          current.file.name.toLowerCase().startsWith("retry-photo") &&
          current.uploadAttempts === 1 &&
          value === 43
        ) {
          throw new PhotoUploadError("upload_failed");
        }
      }
      return;
    }

    const token = await accessToken();
    const config = parsePublicSupabaseConfig(
      process.env.NEXT_PUBLIC_SUPABASE_URL,
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    );
    await new Promise<void>((resolve, reject) => {
      const request = new XMLHttpRequest();
      xhr.current = request;
      request.open("POST", vehiclePhotoStorageUrl(config.url, intent));
      request.setRequestHeader("Authorization", `Bearer ${token}`);
      request.setRequestHeader("apikey", config.anonKey);
      request.setRequestHeader("Content-Type", current.mimeType);
      request.setRequestHeader("x-upsert", "false");
      request.upload.addEventListener("progress", (event) => {
        if (operation.current !== operationId || !event.lengthComputable)
          return;
        setProgress(
          Math.min(99, Math.round((event.loaded / event.total) * 100)),
        );
      });
      request.addEventListener("load", () => {
        xhr.current = null;
        const duplicateObject =
          request.status === 400 &&
          /(already exists|duplicate|resource exists)/iu.test(
            request.responseText,
          );
        if (
          (request.status >= 200 && request.status < 300) ||
          request.status === 409 ||
          duplicateObject
        ) {
          setProgress(100);
          resolve();
        } else {
          reject(new PhotoUploadError("upload_failed"));
        }
      });
      request.addEventListener("error", () => {
        xhr.current = null;
        reject(new PhotoUploadError("upload_failed"));
      });
      request.addEventListener("abort", () => {
        xhr.current = null;
        reject(new PhotoUploadError("upload_failed"));
      });
      request.send(current.file);
    });
  }

  async function runPipeline(current: UploadPipeline): Promise<void> {
    const operationId = ++operation.current;
    setErrorMessage(null);
    setReceipt(null);
    setRetryReason("");
    setRetryReasonError(null);
    setStatusChecking(false);
    setStatusRefreshFailed(false);
    setVerificationStatus(null);
    try {
      if (current.checksumSha256 === null) {
        setPhase("hashing");
        current.checksumSha256 = await sha256Hex(current.file);
        if (operation.current !== operationId) return;
        setChecksum(current.checksumSha256);
      }

      if (current.intent === null) {
        setPhase("requesting_intent");
        const payload = {
          byteSize: current.file.size,
          checksumSha256: current.checksumSha256,
          filename: current.file.name,
          mimeType: current.mimeType,
        } as const;
        if (previewEnabled) {
          await wait(55);
          current.intent = parseVehiclePhotoUploadIntent({
            data: {
              mediaId: PREVIEW_MEDIA_ID,
              upload: {
                bucket: "media-private",
                expiresAt: new Date(Date.now() + 15 * 60_000).toISOString(),
                objectKey: `preview/${inventoryUnitId}/${current.file.name}`,
                requiresAuthenticatedSession: true,
              },
              uploadSessionId: PREVIEW_SESSION_ID,
            },
          });
        } else {
          current.intent = parseVehiclePhotoUploadIntent(
            await command(
              `/api/v1/inventory-units/${inventoryUnitId}/media/upload-intents`,
              payload,
              commandKey(`photo-intent:${inventoryUnitId}`, payload),
            ),
          );
        }
        if (operation.current !== operationId) return;
      }

      if (!current.uploaded) {
        setPhase("uploading");
        setProgress(0);
        await uploadObject(current, current.intent, operationId);
        if (operation.current !== operationId) return;
        current.uploaded = true;
        setUploadComplete(true);
      }

      setPhase("verifying");
      const verificationPayload = {
        uploadSessionId: current.intent.uploadSessionId,
      } as const;
      let nextReceipt: VehiclePhotoVerificationReceipt;
      if (previewEnabled) {
        await wait(80);
        nextReceipt = parseVehiclePhotoVerificationReceipt({
          data: {
            jobId: PREVIEW_JOB_ID,
            jobStatus: "queued",
            mediaId: current.intent.mediaId,
            uploadSessionId: current.intent.uploadSessionId,
          },
        });
      } else {
        nextReceipt = parseVehiclePhotoVerificationReceipt(
          await command(
            `/api/v1/media/${current.intent.mediaId}/complete-upload`,
            verificationPayload,
            commandKey(
              `photo-verification:${current.intent.mediaId}`,
              verificationPayload,
            ),
          ),
        );
      }
      if (operation.current !== operationId) return;
      setStatusChecking(!previewEnabled);
      setReceipt(nextReceipt);
      setPhase("verification_queued");
      onVerificationQueued?.(nextReceipt);
    } catch (error) {
      if (operation.current !== operationId) return;
      const code =
        error instanceof PhotoUploadError ? error.code : "request_failed";
      if (code === "intent_expired" && current.checksumSha256 !== null) {
        const payload = {
          byteSize: current.file.size,
          checksumSha256: current.checksumSha256,
          filename: current.file.name,
          mimeType: current.mimeType,
        } as const;
        clearVehiclePhotoCommandKey(
          idempotency.current,
          `photo-intent:${inventoryUnitId}`,
          payload,
        );
        current.intent = null;
        current.uploaded = false;
        setProgress(0);
        setUploadComplete(false);
      }
      setErrorMessage(
        code === "upload_failed" || code === "intent_expired"
          ? copy.photoUploadError
          : copy.photoRequestError,
      );
      setPhase("error");
    }
  }

  function clearCurrentIntentCommandKey(): void {
    const current = pipeline.current;
    if (current === null || current.checksumSha256 === null) return;
    clearVehiclePhotoCommandKey(
      idempotency.current,
      `photo-intent:${inventoryUnitId}`,
      {
        byteSize: current.file.size,
        checksumSha256: current.checksumSha256,
        filename: current.file.name,
        mimeType: current.mimeType,
      },
    );
  }

  function selectFile(nextFile: File): void {
    operation.current += 1;
    xhr.current?.abort();
    clearCurrentIntentCommandKey();
    const validation = validateVehiclePhotoFile(nextFile);
    setFile(nextFile);
    setChecksum(null);
    setProgress(0);
    setReceipt(null);
    setUploadComplete(false);
    setErrorMessage(null);
    setRetryReason("");
    setRetryReasonError(null);
    setStatusChecking(false);
    setStatusRefreshFailed(false);
    setVerificationStatus(null);
    pipeline.current = null;
    if (!validation.valid) {
      setCanRetry(false);
      setErrorMessage(validationMessage(copy, validation.code));
      setPhase("error");
      return;
    }
    const nextPipeline: UploadPipeline = {
      checksumSha256: null,
      file: nextFile,
      intent: null,
      mimeType: validation.mimeType,
      uploaded: false,
      uploadAttempts: 0,
    };
    pipeline.current = nextPipeline;
    setCanRetry(true);
    void runPipeline(nextPipeline);
  }

  function resetForNewUpload(): void {
    operation.current += 1;
    xhr.current?.abort();
    clearCurrentIntentCommandKey();
    pipeline.current = null;
    if (inputRef.current) inputRef.current.value = "";
    setCanRetry(false);
    setChecksum(null);
    setErrorMessage(null);
    setFile(null);
    setPhase("idle");
    setProgress(0);
    setReceipt(null);
    setRetryReason("");
    setRetryReasonError(null);
    setStatusChecking(false);
    setStatusRefreshFailed(false);
    setUploadComplete(false);
    setVerificationStatus(null);
    window.requestAnimationFrame(() => inputRef.current?.focus());
  }

  async function retryVerification(
    event: FormEvent<HTMLFormElement>,
  ): Promise<void> {
    event.preventDefault();
    if (
      receipt === null ||
      verificationStatus?.status !== "dead_letter" ||
      !verificationStatus.retryable
    ) {
      return;
    }
    const reason = retryReason.trim();
    if (reason.length === 0) {
      setRetryReasonError(copy.photoRetryReasonRequired);
      retryReasonRef.current?.focus();
      return;
    }

    setRetryReasonError(null);
    setRetryingVerification(true);
    setStatusRefreshFailed(false);
    try {
      const payload = { reason } as const;
      const nextReceipt = parseVehiclePhotoVerificationReceipt(
        await command(
          `/api/v1/media/${receipt.mediaId}/upload-sessions/${receipt.uploadSessionId}/retry`,
          payload,
          commandKey(
            `photo-verification-retry:${receipt.uploadSessionId}`,
            payload,
          ),
        ),
      );
      if (
        nextReceipt.mediaId !== receipt.mediaId ||
        nextReceipt.uploadSessionId !== receipt.uploadSessionId
      ) {
        throw new PhotoUploadError("request_failed");
      }
      setRetryReason("");
      setStatusChecking(true);
      setVerificationStatus(null);
      setReceipt(nextReceipt);
      setPhase("verification_queued");
      onVerificationQueued?.(nextReceipt);
    } catch {
      setStatusRefreshFailed(true);
    } finally {
      setRetryingVerification(false);
    }
  }

  const displayedStatus = receipt
    ? (verificationStatus?.status ??
      vehiclePhotoReceiptStatus(receipt.jobStatus))
    : null;
  const statusMessage =
    !previewEnabled && statusChecking && verificationStatus === null
      ? copy.photoStatusChecking
      : displayedStatus
        ? copy[vehiclePhotoStatusMessageKey(displayedStatus)]
        : copy.photoStatusChecking;
  const statusPolls =
    displayedStatus !== null && vehiclePhotoStatusShouldPoll(displayedStatus);
  const displayedJobStatus = displayedStatus
    ? vehiclePhotoProjectedJobStatus(displayedStatus)
    : receipt?.jobStatus;

  const hashState = stageState(
    "hash",
    phase,
    checksum !== null,
    uploadComplete,
    displayedStatus,
  );
  const uploadState = stageState(
    "upload",
    phase,
    checksum !== null,
    uploadComplete,
    displayedStatus,
  );
  const verificationState = stageState(
    "verification",
    phase,
    checksum !== null,
    uploadComplete,
    displayedStatus,
  );
  const phaseDescription =
    phase === "hashing"
      ? copy.photoHashing
      : phase === "requesting_intent"
        ? copy.photoPreparingUpload
        : phase === "uploading"
          ? interpolate(copy.photoUploading, { progress })
          : phase === "verifying"
            ? copy.photoQueueingVerification
            : phase === "verification_queued"
              ? statusRefreshFailed
                ? copy.photoStatusError
                : statusMessage
              : phase === "error"
                ? copy.photoUploadInterrupted
                : copy.photoWaiting;

  return (
    <section
      aria-labelledby={headingId}
      className="vehicle-photo-upload"
      data-phase={phase}
      data-verification-status={displayedStatus ?? undefined}
    >
      <header>
        <p>{copy.photoEyebrow}</p>
        <h2 id={headingId}>{heading ?? copy.photoHeading}</h2>
        <p id={hintId}>{description ?? copy.photoDescription}</p>
      </header>

      <div className="vehicle-photo-upload__workspace">
        <div
          className="vehicle-photo-upload__visual"
          data-selected={Boolean(file)}
        >
          <FileImage aria-hidden="true" size={34} strokeWidth={1.5} />
          {file ? (
            <div>
              <strong>{file.name}</strong>
              <span>{formatBytes(file.size, locale)}</span>
            </div>
          ) : (
            <p>{copy.photoDropHint}</p>
          )}
        </div>

        <div className="vehicle-photo-upload__controls">
          <label className="vehicle-photo-upload__picker">
            <Upload aria-hidden="true" size={17} />
            <span>
              {file ? copy.photoChooseAnotherAction : copy.photoChooseAction}
            </span>
            <Input
              accept={VEHICLE_PHOTO_ACCEPT}
              aria-describedby={hintId}
              disabled={busy}
              onChange={(event) => {
                const nextFile = event.target.files?.[0];
                if (nextFile) selectFile(nextFile);
                event.target.value = "";
              }}
              ref={inputRef}
              type="file"
            />
          </label>
          <span>{copy.photoPolicy}</span>
        </div>
      </div>

      <ol
        aria-label={copy.photoStagesLabel}
        className="vehicle-photo-upload__stages"
      >
        <li data-state={hashState}>
          <span aria-hidden="true">
            {hashState === "complete" ? (
              <Check size={16} />
            ) : (
              <Hash size={16} />
            )}
          </span>
          <div>
            <strong>{copy.photoHashStage}</strong>
            <small>
              {hashState === "complete"
                ? copy.photoHashReady
                : hashState === "current"
                  ? copy.photoHashing
                  : copy.photoWaiting}
            </small>
          </div>
        </li>
        <li data-state={uploadState}>
          <span aria-hidden="true">
            {uploadState === "complete" ? (
              <Check size={16} />
            ) : (
              <Upload size={16} />
            )}
          </span>
          <div>
            <strong>{copy.photoUploadStage}</strong>
            <small>
              {uploadState === "complete"
                ? copy.photoUploadComplete
                : uploadState === "current"
                  ? phaseDescription
                  : copy.photoWaiting}
            </small>
          </div>
        </li>
        <li data-state={verificationState}>
          <span aria-hidden="true">
            {verificationState === "complete" ? (
              <Check size={16} />
            ) : displayedStatus === "dead_letter" ||
              displayedStatus === "rejected" ? (
              <CircleAlert size={16} />
            ) : (
              <ShieldCheck size={16} />
            )}
          </span>
          <div>
            <strong>{copy.photoVerificationStage}</strong>
            <small>
              {phase === "verification_queued"
                ? displayedStatus === "queued" &&
                  !(statusChecking && verificationStatus === null)
                  ? copy.photoVerificationQueued
                  : statusMessage
                : verificationState === "current"
                  ? copy.photoQueueingVerification
                  : copy.photoWaiting}
            </small>
          </div>
        </li>
      </ol>

      {phase === "uploading" ? (
        <div className="vehicle-photo-upload__progress">
          <progress
            aria-label={copy.photoUploadProgressLabel}
            max="100"
            value={progress}
          />
          <span aria-hidden="true">{progress}%</span>
        </div>
      ) : null}

      {checksum ? (
        <dl className="vehicle-photo-upload__receipt">
          <div>
            <dt>{copy.photoChecksumLabel}</dt>
            <dd>
              <code>{checksum}</code>
            </dd>
          </div>
          {receipt ? (
            <div>
              <dt>{copy.photoJobLabel}</dt>
              <dd data-job-status={displayedJobStatus}>
                {vehiclePhotoJobStatusLabel(
                  copy,
                  displayedJobStatus ?? receipt.jobStatus,
                )}
              </dd>
            </div>
          ) : null}
        </dl>
      ) : null}

      <p aria-live="polite" className="vehicle-photo-upload__live">
        {phaseDescription}
      </p>

      {errorMessage ? (
        <div className="vehicle-photo-upload__error" role="alert">
          <CircleAlert aria-hidden="true" size={20} />
          <div>
            <strong>{copy.photoUploadInterrupted}</strong>
            <p>{errorMessage}</p>
          </div>
          {canRetry ? (
            <Button
              disabled={busy}
              onClick={() => {
                const current = pipeline.current;
                if (current) void runPipeline(current);
              }}
              type="button"
            >
              <RotateCcw aria-hidden="true" size={16} />
              {copy.photoRetryAction}
            </Button>
          ) : null}
        </div>
      ) : null}

      {phase === "verification_queued" ? (
        <div
          className="vehicle-photo-upload__queued"
          data-refresh-failed={statusRefreshFailed}
          data-status={displayedStatus}
        >
          <div className="vehicle-photo-upload__status" role="status">
            {displayedStatus === "completed" ? (
              <Check aria-hidden="true" size={20} />
            ) : displayedStatus === "dead_letter" ||
              displayedStatus === "rejected" ? (
              <CircleAlert aria-hidden="true" size={20} />
            ) : statusChecking ||
              displayedStatus === "running" ||
              displayedStatus === "retry_wait" ? (
              <LoaderCircle
                aria-hidden="true"
                className="inventory-intake__spinner"
                size={20}
              />
            ) : (
              <ShieldCheck aria-hidden="true" size={20} />
            )}
            <div>
              <strong>{statusMessage}</strong>
              {statusRefreshFailed ? (
                <p>{copy.photoStatusError}</p>
              ) : statusPolls ? (
                <p>{copy.photoDurableHint}</p>
              ) : null}
            </div>
          </div>

          {displayedStatus === "dead_letter" &&
          verificationStatus?.retryable ? (
            <form
              className="vehicle-photo-upload__retry-form"
              noValidate
              onSubmit={(event) => void retryVerification(event)}
            >
              <label htmlFor={retryReasonId}>
                {copy.photoRetryReasonLabel}
              </label>
              <Textarea
                aria-describedby={
                  retryReasonError ? retryReasonErrorId : undefined
                }
                aria-invalid={retryReasonError ? "true" : undefined}
                aria-required="true"
                disabled={retryingVerification}
                id={retryReasonId}
                maxLength={2000}
                onChange={(event) => {
                  setRetryReason(event.target.value);
                  if (retryReasonError) setRetryReasonError(null);
                }}
                placeholder={copy.photoRetryReasonPlaceholder}
                ref={retryReasonRef}
                rows={3}
                value={retryReason}
              />
              {retryReasonError ? (
                <p id={retryReasonErrorId} role="alert">
                  {retryReasonError}
                </p>
              ) : null}
              <Button disabled={retryingVerification} type="submit">
                {retryingVerification ? (
                  <LoaderCircle
                    aria-hidden="true"
                    className="inventory-intake__spinner"
                    size={16}
                  />
                ) : (
                  <RotateCcw aria-hidden="true" size={16} />
                )}
                {copy.photoRetryVerificationAction}
              </Button>
            </form>
          ) : null}

          {displayedStatus === "rejected" ? (
            <Button onClick={resetForNewUpload} type="button">
              <RotateCcw aria-hidden="true" size={16} />
              {copy.photoStartNewUploadAction}
            </Button>
          ) : null}
        </div>
      ) : null}

      {busy ? (
        <LoaderCircle
          aria-hidden="true"
          className="inventory-intake__spinner vehicle-photo-upload__busy"
          size={18}
        />
      ) : null}
    </section>
  );
}
