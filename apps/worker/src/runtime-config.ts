export interface WorkerRuntimeConfig {
  readonly appUrl: string;
  readonly authInviteTimeoutMs: number;
  readonly batchSize: number;
  readonly errorBackoffBaseMs: number;
  readonly errorBackoffMaximumMs: number;
  readonly documentBucket: string;
  readonly exportBucket: string;
  readonly exportGeneration: Readonly<{
    readonly maximumConcurrentJobs: number;
  }>;
  readonly heartbeatIntervalMs: number;
  readonly leaseSeconds: number;
  readonly mediaProcessing:
    | Readonly<{ readonly enabled: false }>
    | Readonly<{
        readonly clamdConnectTimeoutMs: number;
        readonly clamdHost: string;
        readonly clamdPort: number;
        readonly clamdScanTimeoutMs: number;
        readonly enabled: true;
        readonly maximumConcurrentMediaJobs: number;
      }>;
  readonly pdfRendering: Readonly<{
    readonly maximumConcurrentJobs: number;
    readonly renderer: "playwright";
    readonly timeoutMs: number;
  }>;
  readonly pollIntervalMs: number;
  readonly previewBucket: string;
  readonly serviceRoleKey: string;
  readonly supabaseUrl: string;
  readonly workerId: string;
}

type Environment = Readonly<Record<string, string | undefined>>;

function required(environment: Environment, key: string): string {
  const value = environment[key]?.trim();
  if (!value) {
    throw new TypeError(`Missing required worker environment variable ${key}.`);
  }
  return value;
}

function integer(
  environment: Environment,
  key: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const raw = environment[key];
  const value = raw === undefined || raw.trim() === "" ? fallback : Number(raw);
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(
      `${key} must be an integer from ${minimum} to ${maximum}.`,
    );
  }
  return value;
}

function boolean(
  environment: Environment,
  key: string,
  fallback: boolean,
): boolean {
  const raw = environment[key]?.trim().toLowerCase();
  if (raw === undefined || raw === "") return fallback;
  if (raw === "true") return true;
  if (raw === "false") return false;
  throw new TypeError(`${key} must be true or false.`);
}

export function readWorkerRuntimeConfig(
  environment: Environment,
): WorkerRuntimeConfig {
  const supabaseUrl = required(environment, "VYNLO_SUPABASE_URL");
  const parsedUrl = new URL(supabaseUrl);
  const isLocal = ["127.0.0.1", "localhost", "::1"].includes(
    parsedUrl.hostname,
  );
  if (
    parsedUrl.protocol !== "https:" &&
    !(parsedUrl.protocol === "http:" && isLocal)
  ) {
    throw new TypeError(
      "VYNLO_SUPABASE_URL must use HTTPS outside local development.",
    );
  }

  const appUrl = required(environment, "VYNLO_APP_URL");
  const parsedAppUrl = new URL(appUrl);
  const isLocalApp = ["127.0.0.1", "localhost", "::1"].includes(
    parsedAppUrl.hostname,
  );
  if (
    parsedAppUrl.protocol !== "https:" &&
    !(parsedAppUrl.protocol === "http:" && isLocalApp)
  ) {
    throw new TypeError(
      "VYNLO_APP_URL must use HTTPS outside local development.",
    );
  }
  if (
    parsedAppUrl.username !== "" ||
    parsedAppUrl.password !== "" ||
    parsedAppUrl.pathname !== "/" ||
    parsedAppUrl.search !== "" ||
    parsedAppUrl.hash !== ""
  ) {
    throw new TypeError("VYNLO_APP_URL must be an origin without credentials.");
  }
  if (
    parsedUrl.username !== "" ||
    parsedUrl.password !== "" ||
    parsedUrl.pathname !== "/" ||
    parsedUrl.search !== "" ||
    parsedUrl.hash !== ""
  ) {
    throw new TypeError(
      "VYNLO_SUPABASE_URL must be an origin without credentials.",
    );
  }

  const serviceRoleKey = required(
    environment,
    "VYNLO_SUPABASE_SERVICE_ROLE_KEY",
  );
  if (serviceRoleKey.length < 20) {
    throw new TypeError("VYNLO_SUPABASE_SERVICE_ROLE_KEY is invalid.");
  }
  const workerId = required(environment, "VYNLO_WORKER_ID");
  if (
    workerId.length > 200 ||
    !/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/u.test(workerId)
  ) {
    throw new TypeError(
      "VYNLO_WORKER_ID must be a stable non-secret identifier.",
    );
  }
  const previewBucket = required(environment, "VYNLO_PREVIEW_BUCKET");
  if (!/^[a-z0-9][a-z0-9_-]{2,62}$/u.test(previewBucket)) {
    throw new TypeError("VYNLO_PREVIEW_BUCKET is invalid.");
  }
  const documentBucket = required(environment, "VYNLO_DOCUMENT_BUCKET");
  if (!/^[a-z0-9][a-z0-9_-]{2,62}$/u.test(documentBucket)) {
    throw new TypeError("VYNLO_DOCUMENT_BUCKET is invalid.");
  }
  const exportBucket = required(environment, "VYNLO_EXPORT_BUCKET");
  if (!/^[a-z0-9][a-z0-9_-]{2,62}$/u.test(exportBucket)) {
    throw new TypeError("VYNLO_EXPORT_BUCKET is invalid.");
  }
  const pdfRenderer = required(environment, "PDF_RENDERER");
  if (pdfRenderer !== "playwright") {
    throw new TypeError("PDF_RENDERER must be playwright.");
  }

  const leaseSeconds = integer(
    environment,
    "VYNLO_WORKER_LEASE_SECONDS",
    60,
    5,
    900,
  );
  const heartbeatIntervalMs = integer(
    environment,
    "VYNLO_WORKER_HEARTBEAT_INTERVAL_MS",
    Math.floor((leaseSeconds * 1_000) / 3),
    100,
    Math.floor((leaseSeconds * 1_000) / 2),
  );
  const errorBackoffBaseMs = integer(
    environment,
    "VYNLO_WORKER_ERROR_BACKOFF_BASE_MS",
    1_000,
    100,
    60_000,
  );
  const errorBackoffMaximumMs = integer(
    environment,
    "VYNLO_WORKER_ERROR_BACKOFF_MAX_MS",
    30_000,
    errorBackoffBaseMs,
    300_000,
  );
  const mediaProcessingEnabled = boolean(
    environment,
    "VYNLO_MEDIA_PROCESSING_ENABLED",
    false,
  );
  const mediaProcessing: WorkerRuntimeConfig["mediaProcessing"] =
    mediaProcessingEnabled
      ? {
          clamdConnectTimeoutMs: integer(
            environment,
            "VYNLO_CLAMD_CONNECT_TIMEOUT_MS",
            3_000,
            100,
            30_000,
          ),
          clamdHost: required(environment, "VYNLO_CLAMD_HOST"),
          clamdPort: integer(environment, "VYNLO_CLAMD_PORT", 3_310, 1, 65_535),
          clamdScanTimeoutMs: integer(
            environment,
            "VYNLO_CLAMD_SCAN_TIMEOUT_MS",
            30_000,
            1_000,
            120_000,
          ),
          enabled: true,
          maximumConcurrentMediaJobs: integer(
            environment,
            "VYNLO_MEDIA_JOB_CONCURRENCY",
            1,
            1,
            2,
          ),
        }
      : { enabled: false };

  return {
    appUrl: parsedAppUrl.toString().replace(/\/$/u, ""),
    authInviteTimeoutMs: integer(
      environment,
      "VYNLO_AUTH_INVITE_TIMEOUT_MS",
      10_000,
      1_000,
      30_000,
    ),
    batchSize: integer(environment, "VYNLO_WORKER_BATCH_SIZE", 10, 1, 100),
    documentBucket,
    errorBackoffBaseMs,
    errorBackoffMaximumMs,
    heartbeatIntervalMs,
    leaseSeconds,
    exportBucket,
    exportGeneration: {
      maximumConcurrentJobs: integer(
        environment,
        "VYNLO_EXPORT_JOB_CONCURRENCY",
        2,
        1,
        4,
      ),
    },
    mediaProcessing,
    pdfRendering: {
      maximumConcurrentJobs: integer(
        environment,
        "VYNLO_PDF_JOB_CONCURRENCY",
        2,
        1,
        4,
      ),
      renderer: "playwright",
      timeoutMs: integer(
        environment,
        "VYNLO_PDF_RENDER_TIMEOUT_MS",
        60_000,
        1_000,
        120_000,
      ),
    },
    pollIntervalMs: integer(
      environment,
      "VYNLO_WORKER_POLL_INTERVAL_MS",
      1_000,
      100,
      60_000,
    ),
    previewBucket,
    serviceRoleKey,
    supabaseUrl: parsedUrl.toString().replace(/\/$/u, ""),
    workerId,
  };
}
