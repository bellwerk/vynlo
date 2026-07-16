import { pathToFileURL } from "node:url";

import { createLogger, type Logger } from "@vynlo/observability";

import { GoTrueInvitationDeliveryProvider } from "./gotrue-invitation-delivery-provider";
import {
  createInvitationDeliveryJobHandler,
  INVITATION_DELIVERY_JOB_TYPE,
} from "./invitation-delivery-handler";
import { PostgrestInvitationDeliveryRepository } from "./invitation-delivery-repository";
import { DurableJobRunner } from "./job-runner";
import { PostgrestJobStore } from "./job-store";
import { SupabasePrivateArtifactStorage } from "./private-artifact-storage";
import { PostgrestPreviewDocumentRepository } from "./preview-document-repository";
import { createPreviewJobHandler } from "./preview-handler";
import { PREVIEW_JOB_TYPE } from "./preview-renderer";
import {
  readWorkerRuntimeConfig,
  type WorkerRuntimeConfig,
} from "./runtime-config";
import { WorkerService } from "./worker-service";

export const WORKER_JOB_TYPES = [
  PREVIEW_JOB_TYPE,
  INVITATION_DELIVERY_JOB_TYPE,
] as const;

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
  const invitations = new PostgrestInvitationDeliveryRepository(commonOptions);
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
  const invitationHandler = createInvitationDeliveryJobHandler({
    provider: invitationProvider,
    repository: invitations,
    workerId: input.config.workerId,
  });
  const runner = new DurableJobRunner({
    handlers: new Map([
      [PREVIEW_JOB_TYPE, previewHandler],
      [INVITATION_DELIVERY_JOB_TYPE, invitationHandler],
    ]),
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
  const logger = createLogger("worker");
  const service = createWorkerService({ config, logger });
  const shutdown = new AbortController();
  const stop = () => shutdown.abort();
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);

  logger.info("worker process started", {
    batchSize: config.batchSize,
    jobTypes: WORKER_JOB_TYPES,
    leaseSeconds: config.leaseSeconds,
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
