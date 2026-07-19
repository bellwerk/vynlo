import { pathToFileURL } from "node:url";

import { createLogger, type Logger } from "@vynlo/observability";
import { NhtsaVpicVinDecoderAdapter } from "@vynlo/integrations";

import { ClamdMediaMalwareScanner } from "./clamd-media-malware-scanner";
import { GoTrueInvitationDeliveryProvider } from "./gotrue-invitation-delivery-provider";
import {
  createExportGenerationJobHandler,
  EXPORT_GENERATION_JOB_TYPE,
} from "./export-handler";
import { PostgrestExportRunRepository } from "./export-repository";
import {
  createInvitationDeliveryJobHandler,
  INVITATION_DELIVERY_JOB_TYPE,
} from "./invitation-delivery-handler";
import { PostgrestInvitationDeliveryRepository } from "./invitation-delivery-repository";
import {
  DurableJobRunner,
  type JobExecutionLane,
  type JobHandler,
} from "./job-runner";
import { PostgrestJobStore } from "./job-store";
import {
  createLegalOriginalUploadVerificationJobHandler,
  LEGAL_ORIGINAL_UPLOAD_VERIFICATION_JOB_TYPE,
} from "./legal-original-upload-verification-handler";
import { LEGAL_ORIGINAL_QUARANTINE_CLEANUP_JOB_TYPE } from "./legal-original-quarantine-cleanup-handler";
import { SupabaseImmutableArtifactStorage } from "./immutable-artifact-storage";
import { SupabaseManagedMediaStorage } from "./managed-media-storage";
import {
  createVehiclePhotoJobHandler,
  MEDIA_PROCESSING_JOB_TYPE,
  MEDIA_RAW_RETENTION_JOB_TYPE,
} from "./media-handler";
import { MEDIA_QUARANTINE_CLEANUP_JOB_TYPE } from "./media-quarantine-cleanup-handler";
import { PostgrestMediaRepository } from "./media-repository";
import {
  createMediaUploadVerificationJobHandler,
  MEDIA_UPLOAD_VERIFICATION_JOB_TYPE,
} from "./media-upload-verification-handler";
import { SupabasePrivateArtifactStorage } from "./private-artifact-storage";
import { createOfficialDocumentJobHandler } from "./official-document-handler";
import { PostgrestOfficialDocumentRepository } from "./official-document-repository";
import {
  OFFICIAL_DOCUMENT_JOB_TYPE,
  OfficialDocumentRenderer,
} from "./official-document-renderer";
import { PostgrestPreviewDocumentRepository } from "./preview-document-repository";
import { createPreviewJobHandler } from "./preview-handler";
import { PREVIEW_JOB_TYPE } from "./preview-renderer";
import {
  readWorkerRuntimeConfig,
  type WorkerRuntimeConfig,
} from "./runtime-config";
import {
  assertSharpMediaRuntimeReady,
  SharpVehiclePhotoProcessor,
} from "./sharp-vehicle-photo-processor";
import {
  createVinDecodeJobHandler,
  VIN_DECODE_JOB_TYPE,
} from "./vin-decode-handler";
import { PostgrestVinDecodeResultRepository } from "./vin-decode-repository";
import { WorkerService } from "./worker-service";

export const WORKER_JOB_TYPES = [
  PREVIEW_JOB_TYPE,
  OFFICIAL_DOCUMENT_JOB_TYPE,
  EXPORT_GENERATION_JOB_TYPE,
  INVITATION_DELIVERY_JOB_TYPE,
  VIN_DECODE_JOB_TYPE,
  MEDIA_UPLOAD_VERIFICATION_JOB_TYPE,
  LEGAL_ORIGINAL_UPLOAD_VERIFICATION_JOB_TYPE,
  MEDIA_PROCESSING_JOB_TYPE,
  MEDIA_RAW_RETENTION_JOB_TYPE,
  MEDIA_QUARANTINE_CLEANUP_JOB_TYPE,
  LEGAL_ORIGINAL_QUARANTINE_CLEANUP_JOB_TYPE,
] as const;

/** Declared but deliberately not claimable until storage has atomic If-Match delete. */
export const ATOMIC_DELETE_BLOCKED_JOB_TYPES = [
  MEDIA_RAW_RETENTION_JOB_TYPE,
  MEDIA_QUARANTINE_CLEANUP_JOB_TYPE,
  LEGAL_ORIGINAL_QUARANTINE_CLEANUP_JOB_TYPE,
] as const;

export function enabledWorkerJobTypes(
  config: WorkerRuntimeConfig,
): readonly string[] {
  return WORKER_JOB_TYPES.filter(
    (jobType) =>
      jobType !== MEDIA_RAW_RETENTION_JOB_TYPE &&
      jobType !== MEDIA_QUARANTINE_CLEANUP_JOB_TYPE &&
      jobType !== LEGAL_ORIGINAL_QUARANTINE_CLEANUP_JOB_TYPE &&
      (config.mediaProcessing.enabled ||
        (jobType !== MEDIA_UPLOAD_VERIFICATION_JOB_TYPE &&
          jobType !== LEGAL_ORIGINAL_UPLOAD_VERIFICATION_JOB_TYPE &&
          jobType !== MEDIA_PROCESSING_JOB_TYPE)),
  );
}

export function workerExecutionLanes(
  config: WorkerRuntimeConfig,
  jobTypes: readonly string[],
): readonly JobExecutionLane[] {
  const media = jobTypes.filter((jobType) => jobType.startsWith("media."));
  const pdf = jobTypes.filter(
    (jobType) => jobType === OFFICIAL_DOCUMENT_JOB_TYPE,
  );
  const exports = jobTypes.filter(
    (jobType) => jobType === EXPORT_GENERATION_JOB_TYPE,
  );
  const lightweight = jobTypes.filter(
    (jobType) =>
      !jobType.startsWith("media.") &&
      jobType !== OFFICIAL_DOCUMENT_JOB_TYPE &&
      jobType !== EXPORT_GENERATION_JOB_TYPE,
  );
  return [
    ...(media.length === 0
      ? []
      : [
          {
            jobTypes: media,
            maximumConcurrency: config.mediaProcessing.enabled
              ? config.mediaProcessing.maximumConcurrentMediaJobs
              : 1,
          },
        ]),
    ...(pdf.length === 0
      ? []
      : [
          {
            jobTypes: pdf,
            maximumConcurrency: config.pdfRendering.maximumConcurrentJobs,
          },
        ]),
    ...(exports.length === 0
      ? []
      : [
          {
            jobTypes: exports,
            maximumConcurrency: config.exportGeneration.maximumConcurrentJobs,
          },
        ]),
    ...(lightweight.length === 0
      ? []
      : [{ jobTypes: lightweight, maximumConcurrency: 100 }]),
  ];
}

export async function assertWorkerRuntimeReadiness(
  config: WorkerRuntimeConfig,
): Promise<void> {
  const { chromium } = await import("playwright");
  if (typeof chromium.launch !== "function") {
    throw new TypeError("The Playwright Chromium PDF runtime is unavailable.");
  }
  const browser = await chromium.launch({ headless: true });
  await browser.close();
  if (!config.mediaProcessing.enabled) return;
  assertSharpMediaRuntimeReady();
  await new ClamdMediaMalwareScanner({
    connectTimeoutMs: config.mediaProcessing.clamdConnectTimeoutMs,
    host: config.mediaProcessing.clamdHost,
    port: config.mediaProcessing.clamdPort,
    scanTimeoutMs: config.mediaProcessing.clamdScanTimeoutMs,
  }).assertReady();
}

export function createWorkerService(input: {
  readonly config: WorkerRuntimeConfig;
  readonly fetchImplementation?: typeof fetch;
  readonly logger?: Logger;
}): WorkerService {
  const logger = input.logger ?? createLogger("worker");
  const commonOptions =
    input.fetchImplementation === undefined
      ? {
          serviceRoleKey: input.config.serviceRoleKey,
          supabaseUrl: input.config.supabaseUrl,
        }
      : {
          fetchImplementation: input.fetchImplementation,
          serviceRoleKey: input.config.serviceRoleKey,
          supabaseUrl: input.config.supabaseUrl,
        };
  const store = new PostgrestJobStore(commonOptions);
  const documents = new PostgrestPreviewDocumentRepository(commonOptions);
  const officialDocuments = new PostgrestOfficialDocumentRepository(
    commonOptions,
  );
  const exports = new PostgrestExportRunRepository(commonOptions);
  const invitations = new PostgrestInvitationDeliveryRepository(commonOptions);
  const vinResults = new PostgrestVinDecodeResultRepository(commonOptions);
  const vinDecoder = new NhtsaVpicVinDecoderAdapter(
    input.fetchImplementation === undefined
      ? {}
      : { fetchImplementation: input.fetchImplementation },
  );
  const invitationProvider = new GoTrueInvitationDeliveryProvider({
    ...commonOptions,
    appUrl: input.config.appUrl,
    timeoutMs: input.config.authInviteTimeoutMs,
  });
  const storage = new SupabasePrivateArtifactStorage({
    ...commonOptions,
    bucket: input.config.previewBucket,
  });
  const previewHandler = createPreviewJobHandler({
    documents,
    storage,
    workerId: input.config.workerId,
  });
  const officialDocumentStorage = new SupabaseImmutableArtifactStorage({
    ...commonOptions,
    allowedContentTypes: ["application/pdf"],
    bucket: input.config.documentBucket,
    maximumBytes: 52_428_800,
  });
  const exportStorage = new SupabaseImmutableArtifactStorage({
    ...commonOptions,
    allowedContentTypes: [
      "text/csv; charset=utf-8",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ],
    bucket: input.config.exportBucket,
    maximumBytes: 104_857_600,
  });
  const officialDocumentHandler = createOfficialDocumentJobHandler({
    documents: officialDocuments,
    renderer: new OfficialDocumentRenderer({
      timeoutMs: input.config.pdfRendering.timeoutMs,
    }),
    storage: officialDocumentStorage,
    workerId: input.config.workerId,
  });
  const exportHandler = createExportGenerationJobHandler({
    exports,
    storage: exportStorage,
    workerId: input.config.workerId,
  });
  const invitationHandler = createInvitationDeliveryJobHandler({
    provider: invitationProvider,
    repository: invitations,
    workerId: input.config.workerId,
  });
  const vinDecodeHandler = createVinDecodeJobHandler({
    decoder: vinDecoder,
    repository: vinResults,
    workerId: input.config.workerId,
  });
  const handlers = new Map<string, JobHandler>([
    [PREVIEW_JOB_TYPE, previewHandler],
    [OFFICIAL_DOCUMENT_JOB_TYPE, officialDocumentHandler],
    [EXPORT_GENERATION_JOB_TYPE, exportHandler],
    [INVITATION_DELIVERY_JOB_TYPE, invitationHandler],
    [VIN_DECODE_JOB_TYPE, vinDecodeHandler],
  ]);
  if (input.config.mediaProcessing.enabled) {
    const mediaStorage = new SupabaseManagedMediaStorage(commonOptions);
    const mediaRepository = new PostgrestMediaRepository(commonOptions);
    const mediaScanner = new ClamdMediaMalwareScanner({
      connectTimeoutMs: input.config.mediaProcessing.clamdConnectTimeoutMs,
      host: input.config.mediaProcessing.clamdHost,
      port: input.config.mediaProcessing.clamdPort,
      scanTimeoutMs: input.config.mediaProcessing.clamdScanTimeoutMs,
    });
    handlers.set(
      MEDIA_UPLOAD_VERIFICATION_JOB_TYPE,
      createMediaUploadVerificationJobHandler({
        repository: mediaRepository.mediaUploadVerificationRepository(),
        scanner: mediaScanner,
        storage: mediaStorage,
        workerId: input.config.workerId,
      }),
    );
    handlers.set(
      LEGAL_ORIGINAL_UPLOAD_VERIFICATION_JOB_TYPE,
      createLegalOriginalUploadVerificationJobHandler({
        repository: mediaRepository.legalOriginalUploadVerificationRepository(),
        scanner: mediaScanner,
        storage: mediaStorage,
        workerId: input.config.workerId,
      }),
    );
    handlers.set(
      MEDIA_PROCESSING_JOB_TYPE,
      createVehiclePhotoJobHandler({
        processor: new SharpVehiclePhotoProcessor(),
        repository: mediaRepository,
        scanner: mediaScanner,
        storage: mediaStorage,
        workerId: input.config.workerId,
      }),
    );
  }
  const runner = new DurableJobRunner({
    executionLanes: workerExecutionLanes(input.config, [...handlers.keys()]),
    handlers,
    heartbeatIntervalMs: input.config.heartbeatIntervalMs,
    leaseSeconds: input.config.leaseSeconds,
    logger,
    store,
    workerId: input.config.workerId,
  });
  return new WorkerService({
    batchSize: input.config.batchSize,
    errorBackoffBaseMs: input.config.errorBackoffBaseMs,
    errorBackoffMaximumMs: input.config.errorBackoffMaximumMs,
    logger,
    pollIntervalMs: input.config.pollIntervalMs,
    runner,
  });
}

export async function runWorkerProcess(
  environment: Readonly<Record<string, string | undefined>> = process.env,
): Promise<void> {
  const config = readWorkerRuntimeConfig(environment);
  await assertWorkerRuntimeReadiness(config);
  const logger = createLogger("worker");
  const service = createWorkerService({ config, logger });
  const shutdown = new AbortController();
  const stop = () => shutdown.abort();
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);

  logger.info("worker process started", {
    batchSize: config.batchSize,
    jobTypes: enabledWorkerJobTypes(config),
    leaseSeconds: config.leaseSeconds,
    maximumConcurrentMediaJobs: config.mediaProcessing.enabled
      ? config.mediaProcessing.maximumConcurrentMediaJobs
      : 0,
    maximumConcurrentPdfJobs: config.pdfRendering.maximumConcurrentJobs,
    maximumConcurrentExportJobs: config.exportGeneration.maximumConcurrentJobs,
    workerId: config.workerId,
  });
  try {
    await service.run(shutdown.signal);
  } finally {
    process.removeListener("SIGINT", stop);
    process.removeListener("SIGTERM", stop);
  }
}

export function isDirectWorkerEntrypoint(
  moduleUrl: string,
  argvEntry: string | undefined,
): boolean {
  return argvEntry !== undefined && moduleUrl === pathToFileURL(argvEntry).href;
}

if (isDirectWorkerEntrypoint(import.meta.url, process.argv[1])) {
  void runWorkerProcess().catch(() => {
    process.stderr.write(
      `${JSON.stringify({ level: "error", message: "worker process stopped unexpectedly", service: "worker" })}\n`,
    );
    process.exitCode = 1;
  });
}
