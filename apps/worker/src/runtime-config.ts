export interface WorkerRuntimeConfig {
  readonly appUrl: string;
  readonly authInviteTimeoutMs: number;
  readonly batchSize: number;
  readonly errorBackoffBaseMs: number;
  readonly errorBackoffMaximumMs: number;
  readonly heartbeatIntervalMs: number;
  readonly leaseSeconds: number;
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
    errorBackoffBaseMs,
    errorBackoffMaximumMs,
    heartbeatIntervalMs,
    leaseSeconds,
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
