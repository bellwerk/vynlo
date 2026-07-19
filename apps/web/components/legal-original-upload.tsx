"use client";

import { Button } from "@vynlo/ui-web/components/button";
import { Input } from "@vynlo/ui-web/components/input";
import { NativeSelect } from "@vynlo/ui-web/components/native-select";
import {
  RadioGroup,
  RadioGroupItem,
} from "@vynlo/ui-web/components/radio-group";
import { Textarea } from "@vynlo/ui-web/components/textarea";
import {
  Check,
  CircleAlert,
  FileLock2,
  Hash,
  LoaderCircle,
  RotateCcw,
  ShieldCheck,
  Upload,
} from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState, type FormEvent } from "react";

import type { LegalOriginalUploadCopy } from "../i18n/legal-original-messages";
import {
  getBrowserSupabase,
  parsePublicSupabaseConfig,
} from "../lib/supabase-browser";
import {
  LEGAL_ORIGINAL_ACCEPT,
  legalOriginalSha256Hex,
  legalOriginalReceiptStatus,
  legalOriginalStorageUrl,
  legalOriginalStatusMessageKey,
  legalOriginalStatusShouldPoll,
  parseLegalOriginalUploadIntent,
  parseLegalOriginalVerificationReceipt,
  parseLegalOriginalVerificationStatus,
  validateLegalOriginalFile,
  type LegalOriginalMimeType,
  type LegalOriginalUploadIntent,
  type LegalOriginalValidationErrorCode,
  type LegalOriginalVerificationReceipt,
  type LegalOriginalVerificationStatus,
} from "../lib/legal-original-upload";

export interface LegalOriginalDocumentOption {
  readonly id: string;
  readonly status: string;
  readonly watermark: string;
}

type MediaKind = "legal_document" | "signed_document";
type Phase =
  | "error"
  | "hashing"
  | "idle"
  | "queueing"
  | "queued"
  | "requesting_intent"
  | "uploading";

interface Pipeline {
  checksumSha256: string | null;
  readonly documentId: string;
  readonly file: File;
  intent: LegalOriginalUploadIntent | null;
  readonly mediaKind: MediaKind;
  readonly mimeType: LegalOriginalMimeType;
  uploaded: boolean;
}

class LegalUploadError extends Error {
  readonly code:
    "intent_expired" | "request_failed" | "step_up" | "upload_failed";

  constructor(code: LegalUploadError["code"]) {
    super(code);
    this.name = "LegalUploadError";
    this.code = code;
  }
}

function validationMessage(
  copy: LegalOriginalUploadCopy,
  code: LegalOriginalValidationErrorCode,
): string {
  switch (code) {
    case "file_empty":
      return copy.fileEmptyError;
    case "file_too_large":
      return copy.fileSizeError;
    case "unsupported_file_type":
      return copy.fileTypeError;
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
  stage: "hash" | "upload" | "verify",
  phase: Phase,
  checksumReady: boolean,
  uploaded: boolean,
): "complete" | "current" | "waiting" {
  if (stage === "hash") {
    if (phase === "hashing") return "current";
    return checksumReady ? "complete" : "waiting";
  }
  if (stage === "upload") {
    if (phase === "requesting_intent" || phase === "uploading")
      return "current";
    return uploaded ? "complete" : "waiting";
  }
  return phase === "queued"
    ? "complete"
    : phase === "queueing"
      ? "current"
      : "waiting";
}

export function LegalOriginalUpload({
  canCreateLegal,
  canUploadSigned,
  copy,
  documents,
  locale,
  workspaceId,
}: Readonly<{
  canCreateLegal: boolean;
  canUploadSigned: boolean;
  copy: LegalOriginalUploadCopy;
  documents: readonly LegalOriginalDocumentOption[];
  locale: "en" | "fr";
  workspaceId: string;
}>) {
  const router = useRouter();
  const headingId = useId();
  const hintId = useId();
  const fileInput = useRef<HTMLInputElement | null>(null);
  const idempotency = useRef(new Map<string, string>());
  const operation = useRef(0);
  const pipeline = useRef<Pipeline | null>(null);
  const xhr = useRef<XMLHttpRequest | null>(null);
  const [canRetry, setCanRetry] = useState(false);
  const [checksum, setChecksum] = useState<string | null>(null);
  const [documentId, setDocumentId] = useState(documents[0]?.id ?? "");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [file, setFile] = useState<File | null>(null);
  const [mediaKind, setMediaKind] = useState<MediaKind>("legal_document");
  const [phase, setPhase] = useState<Phase>("idle");
  const [progress, setProgress] = useState(0);
  const [receipt, setReceipt] =
    useState<LegalOriginalVerificationReceipt | null>(null);
  const [retryReason, setRetryReason] = useState("");
  const [retryReasonError, setRetryReasonError] = useState<string | null>(null);
  const [retryingVerification, setRetryingVerification] = useState(false);
  const [statusChecking, setStatusChecking] = useState(false);
  const [statusRefreshFailed, setStatusRefreshFailed] = useState(false);
  const [statusStepUpRequired, setStatusStepUpRequired] = useState(false);
  const [verificationStatus, setVerificationStatus] =
    useState<LegalOriginalVerificationStatus | null>(null);
  const [uploaded, setUploaded] = useState(false);

  const busy =
    ["hashing", "queueing", "requesting_intent", "uploading"].includes(phase) ||
    retryingVerification;
  const permitted =
    mediaKind === "signed_document" ? canUploadSigned : canCreateLegal;

  const effectiveDocumentId = documents.some(
    (document) => document.id === documentId,
  )
    ? documentId
    : (documents[0]?.id ?? "");

  useEffect(
    () => () => {
      operation.current += 1;
      xhr.current?.abort();
    },
    [],
  );

  function resetPipeline(): void {
    operation.current += 1;
    xhr.current?.abort();
    xhr.current = null;
    if (fileInput.current) fileInput.current.value = "";
    pipeline.current = null;
    setCanRetry(false);
    setChecksum(null);
    setErrorMessage(null);
    setFile(null);
    setPhase("idle");
    setProgress(0);
    setReceipt(null);
    setRetryReason("");
    setRetryReasonError(null);
    setRetryingVerification(false);
    setStatusChecking(false);
    setStatusRefreshFailed(false);
    setStatusStepUpRequired(false);
    setVerificationStatus(null);
    setUploaded(false);
  }

  function commandKey(scope: string, payload: unknown): string {
    const cacheKey = `${scope}:${JSON.stringify(payload)}`;
    const previous = idempotency.current.get(cacheKey);
    if (previous) return previous;
    const next = crypto.randomUUID();
    idempotency.current.set(cacheKey, next);
    return next;
  }

  function clearCommandKey(scope: string, payload: unknown): void {
    idempotency.current.delete(`${scope}:${JSON.stringify(payload)}`);
  }

  async function accessToken(): Promise<string> {
    const session = (await getBrowserSupabase().auth.getSession()).data.session;
    if (!session) {
      router.replace("/login");
      throw new LegalUploadError("request_failed");
    }
    return session.access_token;
  }

  async function command(
    path: string,
    payload: unknown,
    key: string,
  ): Promise<unknown> {
    const response = await fetch(path, {
      body: JSON.stringify(payload),
      headers: {
        Authorization: `Bearer ${await accessToken()}`,
        "Content-Type": "application/json",
        "Idempotency-Key": key,
        "X-Correlation-Id": crypto.randomUUID(),
        "X-Request-Id": crypto.randomUUID(),
        "X-Workspace-Id": workspaceId,
      },
      method: "POST",
    });
    const envelope: unknown = await response.json().catch(() => null);
    if (!response.ok) {
      throw new LegalUploadError(
        response.status === 403 && mediaKind === "signed_document"
          ? "step_up"
          : "request_failed",
      );
    }
    return envelope;
  }

  useEffect(() => {
    const uploadReceipt = receipt;
    if (phase !== "queued" || uploadReceipt === null) return;

    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const schedule = (delay: number, refresh: () => Promise<void>) => {
      timer = setTimeout(() => void refresh(), delay);
    };
    const refresh = async (): Promise<void> => {
      if (stopped) return;
      setStatusChecking(true);
      try {
        const session = (await getBrowserSupabase().auth.getSession()).data
          .session;
        if (!session) {
          router.replace("/login");
          return;
        }
        const response = await fetch(
          `/api/v1/documents/${uploadReceipt.documentId}/original-upload-sessions/${uploadReceipt.uploadSessionId}`,
          {
            cache: "no-store",
            headers: {
              Accept: "application/json",
              Authorization: `Bearer ${session.access_token}`,
              "X-Correlation-Id": crypto.randomUUID(),
              "X-Request-Id": crypto.randomUUID(),
              "X-Workspace-Id": workspaceId,
            },
          },
        );
        const envelope: unknown = await response.json().catch(() => null);
        if (response.status === 403 && mediaKind === "signed_document") {
          if (!stopped) {
            setStatusRefreshFailed(false);
            setStatusStepUpRequired(true);
          }
          return;
        }
        if (!response.ok) throw new LegalUploadError("request_failed");
        const nextStatus = parseLegalOriginalVerificationStatus(envelope);
        if (
          nextStatus.documentId !== uploadReceipt.documentId ||
          nextStatus.uploadSessionId !== uploadReceipt.uploadSessionId
        ) {
          throw new LegalUploadError("request_failed");
        }
        if (stopped) return;
        setVerificationStatus(nextStatus);
        setStatusRefreshFailed(false);
        setStatusStepUpRequired(false);
        if (legalOriginalStatusShouldPoll(nextStatus.status)) {
          schedule(2_000, refresh);
        }
      } catch {
        if (!stopped) {
          setStatusRefreshFailed(true);
          schedule(4_000, refresh);
        }
      } finally {
        if (!stopped) setStatusChecking(false);
      }
    };

    void refresh();
    return () => {
      stopped = true;
      if (timer !== undefined) clearTimeout(timer);
    };
  }, [mediaKind, phase, receipt, router, workspaceId]);

  async function uploadObject(
    current: Pipeline,
    intent: LegalOriginalUploadIntent,
    operationId: number,
  ): Promise<void> {
    if (Date.parse(intent.expiresAt) <= Date.now()) {
      throw new LegalUploadError("intent_expired");
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
      request.open("POST", legalOriginalStorageUrl(config.url, intent));
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
          return;
        }
        reject(
          new LegalUploadError(
            request.status === 403 && current.mediaKind === "signed_document"
              ? "step_up"
              : "upload_failed",
          ),
        );
      });
      request.addEventListener("error", () =>
        reject(new LegalUploadError("upload_failed")),
      );
      request.addEventListener("abort", () =>
        reject(new LegalUploadError("upload_failed")),
      );
      request.send(current.file);
    });
  }

  async function runPipeline(current: Pipeline): Promise<void> {
    const operationId = ++operation.current;
    setErrorMessage(null);
    setReceipt(null);
    setStatusRefreshFailed(false);
    setStatusStepUpRequired(false);
    setVerificationStatus(null);
    try {
      if (current.checksumSha256 === null) {
        setPhase("hashing");
        current.checksumSha256 = await legalOriginalSha256Hex(current.file);
        if (operation.current !== operationId) return;
        setChecksum(current.checksumSha256);
      }

      const intentPayload = {
        byteSize: current.file.size,
        checksumSha256: current.checksumSha256,
        filename: current.file.name,
        mediaKind: current.mediaKind,
        mimeType: current.mimeType,
      } as const;
      const intentScope = `legal-original-intent:${current.documentId}`;
      if (current.intent === null) {
        setPhase("requesting_intent");
        current.intent = parseLegalOriginalUploadIntent(
          await command(
            `/api/v1/documents/${current.documentId}/original-upload-intents`,
            intentPayload,
            commandKey(intentScope, intentPayload),
          ),
        );
        if (
          current.intent.documentId !== current.documentId ||
          current.intent.mediaKind !== current.mediaKind
        ) {
          throw new LegalUploadError("request_failed");
        }
        if (operation.current !== operationId) return;
      }

      if (!current.uploaded) {
        setPhase("uploading");
        setProgress(0);
        await uploadObject(current, current.intent, operationId);
        if (operation.current !== operationId) return;
        current.uploaded = true;
        setUploaded(true);
      }

      setPhase("queueing");
      const verificationPayload = {
        uploadSessionId: current.intent.uploadSessionId,
      } as const;
      const nextReceipt = parseLegalOriginalVerificationReceipt(
        await command(
          `/api/v1/documents/${current.documentId}/original-upload-completions`,
          verificationPayload,
          commandKey(
            `legal-original-verification:${current.documentId}`,
            verificationPayload,
          ),
        ),
      );
      if (
        nextReceipt.documentId !== current.documentId ||
        nextReceipt.uploadSessionId !== current.intent.uploadSessionId
      ) {
        throw new LegalUploadError("request_failed");
      }
      if (operation.current !== operationId) return;
      setReceipt(nextReceipt);
      setPhase("queued");
    } catch (error) {
      if (operation.current !== operationId) return;
      const code =
        error instanceof LegalUploadError ? error.code : "request_failed";
      if (code === "intent_expired") {
        clearCommandKey(`legal-original-intent:${current.documentId}`, {
          byteSize: current.file.size,
          checksumSha256: current.checksumSha256,
          filename: current.file.name,
          mediaKind: current.mediaKind,
          mimeType: current.mimeType,
        });
        current.intent = null;
        current.uploaded = false;
        setUploaded(false);
      }
      setErrorMessage(
        code === "step_up" ? copy.signedStepUp : copy.uploadError,
      );
      setPhase("error");
    }
  }

  function submit(event: FormEvent<HTMLFormElement>): void {
    event.preventDefault();
    if (!file || !effectiveDocumentId || !permitted) return;
    const validation = validateLegalOriginalFile(file);
    if (!validation.valid) {
      setErrorMessage(validationMessage(copy, validation.code));
      setPhase("error");
      return;
    }
    const current: Pipeline = {
      checksumSha256: null,
      documentId: effectiveDocumentId,
      file,
      intent: null,
      mediaKind,
      mimeType: validation.mimeType,
      uploaded: false,
    };
    pipeline.current = current;
    setCanRetry(true);
    void runPipeline(current);
  }

  async function retryVerification(
    event: FormEvent<HTMLFormElement>,
  ): Promise<void> {
    event.preventDefault();
    const uploadReceipt = receipt;
    const reason = retryReason.trim();
    if (uploadReceipt === null || verificationStatus?.retryable !== true)
      return;
    if (reason.length < 1) {
      setRetryReasonError(copy.retryReasonRequired);
      return;
    }
    const payload = { reason } as const;
    setRetryingVerification(true);
    setRetryReasonError(null);
    try {
      const nextReceipt = parseLegalOriginalVerificationReceipt(
        await command(
          `/api/v1/documents/${uploadReceipt.documentId}/original-upload-sessions/${uploadReceipt.uploadSessionId}/retry`,
          payload,
          commandKey(
            `legal-original-verification-retry:${uploadReceipt.documentId}:${uploadReceipt.uploadSessionId}`,
            payload,
          ),
        ),
      );
      if (
        nextReceipt.documentId !== uploadReceipt.documentId ||
        nextReceipt.uploadSessionId !== uploadReceipt.uploadSessionId
      ) {
        throw new LegalUploadError("request_failed");
      }
      setReceipt(nextReceipt);
      setRetryReason("");
      setStatusRefreshFailed(false);
      setStatusStepUpRequired(false);
      setVerificationStatus(null);
    } catch (error) {
      setRetryReasonError(
        error instanceof LegalUploadError && error.code === "step_up"
          ? copy.signedStepUp
          : copy.statusError,
      );
    } finally {
      setRetryingVerification(false);
    }
  }

  const displayedStatus = receipt
    ? (verificationStatus?.status ??
      legalOriginalReceiptStatus(receipt.jobStatus))
    : null;
  const statusMessage = displayedStatus
    ? copy[legalOriginalStatusMessageKey(displayedStatus)]
    : copy.statusChecking;
  const hashState = stageState("hash", phase, checksum !== null, uploaded);
  const uploadState = stageState("upload", phase, checksum !== null, uploaded);
  const verificationState =
    phase === "queued"
      ? displayedStatus === "completed"
        ? "complete"
        : displayedStatus === "dead_letter" || displayedStatus === "rejected"
          ? "waiting"
          : "current"
      : stageState("verify", phase, checksum !== null, uploaded);
  const liveMessage =
    phase === "hashing"
      ? copy.preparing
      : phase === "requesting_intent"
        ? copy.preparing
        : phase === "uploading"
          ? `${copy.uploading} ${progress}%`
          : phase === "queueing"
            ? copy.queueing
            : phase === "queued"
              ? statusChecking && verificationStatus === null
                ? copy.statusChecking
                : statusMessage
              : phase === "error"
                ? errorMessage
                : copy.waiting;

  return (
    <section
      aria-labelledby={headingId}
      className="legal-original-upload"
      data-phase={phase}
    >
      <header>
        <FileLock2 aria-hidden="true" size={26} strokeWidth={1.6} />
        <div>
          <p>{copy.eyebrow}</p>
          <h2 id={headingId}>{copy.heading}</h2>
          <p id={hintId}>{copy.description}</p>
        </div>
      </header>

      <form onSubmit={submit}>
        <label>
          <span>{copy.documentLabel}</span>
          <NativeSelect
            disabled={busy || documents.length === 0}
            onChange={(event) => {
              resetPipeline();
              setDocumentId(event.target.value);
            }}
            value={effectiveDocumentId}
          >
            {documents.map((document) => (
              <option key={document.id} value={document.id}>
                {document.watermark} · {document.id.slice(0, 8)}
              </option>
            ))}
          </NativeSelect>
        </label>

        <fieldset>
          <legend>{copy.mediaKindLabel}</legend>
          <RadioGroup
            className="legal-original-upload__kinds"
            disabled={busy}
            name="media-kind"
            orientation="horizontal"
            onValueChange={(value) => {
              resetPipeline();
              setMediaKind(value as MediaKind);
            }}
            value={mediaKind}
          >
            <label>
              <RadioGroupItem value="legal_document" />
              <span>{copy.legalKind}</span>
            </label>
            <label>
              <RadioGroupItem value="signed_document" />
              <span>{copy.signedKind}</span>
            </label>
          </RadioGroup>
        </fieldset>

        <label className="legal-original-upload__file">
          <span>{copy.fileLabel}</span>
          <Input
            accept={LEGAL_ORIGINAL_ACCEPT}
            aria-describedby={hintId}
            disabled={busy || !effectiveDocumentId || !permitted}
            onChange={(event) => {
              const nextFile = event.target.files?.[0] ?? null;
              setFile(nextFile);
              setCanRetry(false);
              setChecksum(null);
              setErrorMessage(null);
              setPhase("idle");
              setProgress(0);
              setReceipt(null);
              setRetryReason("");
              setRetryReasonError(null);
              setStatusRefreshFailed(false);
              setStatusStepUpRequired(false);
              setVerificationStatus(null);
              setUploaded(false);
              pipeline.current = null;
              if (!nextFile) return;
              const validation = validateLegalOriginalFile(nextFile);
              if (!validation.valid) {
                setErrorMessage(validationMessage(copy, validation.code));
                setPhase("error");
              }
            }}
            ref={fileInput}
            type="file"
          />
        </label>

        {file ? (
          <p className="legal-original-upload__selection">
            <strong>{file.name}</strong>
            <span>{formatBytes(file.size, locale)}</span>
          </p>
        ) : null}

        {mediaKind === "signed_document" ? (
          <p className="legal-original-upload__step-up">
            <ShieldCheck aria-hidden="true" size={18} />
            {copy.signedStepUp}
          </p>
        ) : null}
        {!permitted ? (
          <p className="legal-original-upload__permission" role="status">
            {copy.permissionDenied}
          </p>
        ) : null}
        {documents.length === 0 ? <p>{copy.emptyDocuments}</p> : null}

        <Button
          disabled={busy || !effectiveDocumentId || !file || !permitted}
          type="submit"
        >
          {busy ? (
            <LoaderCircle
              aria-hidden="true"
              className="legal-original-upload__spin"
              size={17}
            />
          ) : (
            <Upload aria-hidden="true" size={17} />
          )}
          {copy.action}
        </Button>
      </form>

      <ol
        aria-label={copy.stagesLabel}
        className="legal-original-upload__stages"
      >
        {[
          [
            copy.stageHash,
            hashState,
            <Hash aria-hidden="true" key="hash" size={15} />,
          ],
          [
            copy.stageUpload,
            uploadState,
            <Upload aria-hidden="true" key="upload" size={15} />,
          ],
          [
            copy.stageQueued,
            verificationState,
            <ShieldCheck aria-hidden="true" key="verify" size={15} />,
          ],
        ].map(([label, state, icon]) => (
          <li data-state={state} key={String(label)}>
            <span>
              {state === "complete" ? (
                <Check aria-hidden="true" size={15} />
              ) : (
                icon
              )}
            </span>
            <strong>{label}</strong>
          </li>
        ))}
      </ol>

      {phase === "uploading" ? (
        <div className="legal-original-upload__progress">
          <progress
            aria-label={copy.uploadProgressLabel}
            max="100"
            value={progress}
          />
          <span aria-hidden="true">{progress}%</span>
        </div>
      ) : null}

      {checksum ? (
        <dl className="legal-original-upload__receipt">
          <div>
            <dt>{copy.checksumLabel}</dt>
            <dd>
              <code>{checksum}</code>
            </dd>
          </div>
          {receipt ? (
            <div>
              <dt>{copy.jobLabel}</dt>
              <dd>
                {receipt.jobId.slice(0, 8)}
                {verificationStatus?.job
                  ? ` · ${verificationStatus.job.attemptCount}/${verificationStatus.job.maximumAttempts}`
                  : null}
              </dd>
            </div>
          ) : null}
        </dl>
      ) : null}

      <p aria-live="polite" className="legal-original-upload__live">
        {liveMessage}
      </p>

      {errorMessage ? (
        <div className="legal-original-upload__error" role="alert">
          <CircleAlert aria-hidden="true" size={19} />
          <p>{errorMessage}</p>
          {canRetry ? (
            <Button
              disabled={busy}
              onClick={() => {
                const current = pipeline.current;
                if (current) void runPipeline(current);
              }}
              type="button"
              variant="outline"
            >
              <RotateCcw aria-hidden="true" size={16} />
              {copy.retryAction}
            </Button>
          ) : null}
        </div>
      ) : null}

      {phase === "queued" ? (
        <div
          aria-busy={statusChecking}
          className="legal-original-upload__queued"
          data-status={displayedStatus}
          role="status"
        >
          {displayedStatus === "completed" ? (
            <Check aria-hidden="true" size={19} />
          ) : displayedStatus === "dead_letter" ||
            displayedStatus === "rejected" ? (
            <CircleAlert aria-hidden="true" size={19} />
          ) : statusChecking || displayedStatus === "running" ? (
            <LoaderCircle
              aria-hidden="true"
              className="legal-original-upload__spin"
              size={19}
            />
          ) : (
            <ShieldCheck aria-hidden="true" size={19} />
          )}
          <div>
            <strong>{statusMessage}</strong>
            {statusStepUpRequired ? (
              <p>{copy.signedStepUp}</p>
            ) : statusRefreshFailed ? (
              <p>{copy.statusError}</p>
            ) : displayedStatus === "queued" ||
              displayedStatus === "running" ||
              displayedStatus === "retry_wait" ? (
              <p>{copy.queuedHint}</p>
            ) : null}
          </div>
        </div>
      ) : null}

      {phase === "queued" && verificationStatus?.retryable ? (
        <form
          className="legal-original-upload__retry"
          onSubmit={(event) => void retryVerification(event)}
        >
          <label>
            <span>{copy.retryReasonLabel}</span>
            <Textarea
              aria-invalid={retryReasonError !== null}
              disabled={retryingVerification}
              maxLength={2_000}
              onChange={(event) => {
                setRetryReason(event.target.value);
                setRetryReasonError(null);
              }}
              placeholder={copy.retryReasonPlaceholder}
              required
              rows={3}
              value={retryReason}
            />
          </label>
          {retryReasonError ? (
            <p className="legal-original-upload__retry-error" role="alert">
              {retryReasonError}
            </p>
          ) : null}
          <Button
            disabled={retryingVerification}
            type="submit"
            variant="outline"
          >
            {retryingVerification ? (
              <LoaderCircle
                aria-hidden="true"
                className="legal-original-upload__spin"
                size={16}
              />
            ) : (
              <RotateCcw aria-hidden="true" size={16} />
            )}
            {copy.retryVerificationAction}
          </Button>
        </form>
      ) : null}

      {phase === "queued" && displayedStatus === "rejected" ? (
        <Button onClick={resetPipeline} type="button" variant="outline">
          <RotateCcw aria-hidden="true" size={16} />
          {copy.startNewUploadAction}
        </Button>
      ) : null}

      <p className="legal-original-upload__policy">{copy.policy}</p>
    </section>
  );
}
