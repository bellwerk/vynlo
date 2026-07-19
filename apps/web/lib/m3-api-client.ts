export interface M3ApiContext {
  readonly accessToken: string;
  readonly workspaceId: string;
}

export type M3ApiErrorCode =
  | "authentication_required"
  | "conflict"
  | "invalid_request"
  | "not_found"
  | "offline"
  | "permission_denied"
  | "service_unavailable"
  | "unprocessable_command";

export class M3ApiError extends Error {
  readonly code: M3ApiErrorCode;
  readonly correlationId: string;
  readonly status: number;

  constructor(input: {
    readonly code: M3ApiErrorCode;
    readonly correlationId: string;
    readonly status: number;
  }) {
    super(input.code);
    this.name = "M3ApiError";
    this.code = input.code;
    this.correlationId = input.correlationId;
    this.status = input.status;
  }
}

function record(value: unknown): Readonly<Record<string, unknown>> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Readonly<Record<string, unknown>>)
    : null;
}

function safeErrorCode(value: unknown, status: number): M3ApiErrorCode {
  const known: readonly M3ApiErrorCode[] = [
    "authentication_required",
    "conflict",
    "invalid_request",
    "not_found",
    "permission_denied",
    "service_unavailable",
    "unprocessable_command",
  ];
  return typeof value === "string" && known.includes(value as M3ApiErrorCode)
    ? (value as M3ApiErrorCode)
    : status === 409
      ? "conflict"
      : status === 401
        ? "authentication_required"
        : status === 403
          ? "permission_denied"
          : status === 404
            ? "not_found"
            : status === 422
              ? "unprocessable_command"
              : "service_unavailable";
}

export function newM3IdempotencyKey(prefix: string): string {
  const normalized = prefix
    .trim()
    .toLowerCase()
    .replaceAll(/[^a-z0-9_-]/gu, "-")
    .slice(0, 40);
  return `${normalized || "m3-command"}-${crypto.randomUUID()}`;
}

export async function requestM3Json<T>(input: {
  readonly body?: unknown;
  readonly context: M3ApiContext;
  readonly idempotencyKey?: string;
  readonly method?: "DELETE" | "GET" | "PATCH" | "POST";
  readonly path: string;
}): Promise<T> {
  const correlationId = crypto.randomUUID();
  const requestId = `browser-${crypto.randomUUID()}`;
  const method = input.method ?? "GET";
  const headers = new Headers({
    Authorization: `Bearer ${input.context.accessToken}`,
    "X-Correlation-Id": correlationId,
    "X-Request-Id": requestId,
    "X-Workspace-Id": input.context.workspaceId,
  });
  if (method !== "GET") {
    headers.set("Content-Type", "application/json");
    headers.set(
      "Idempotency-Key",
      input.idempotencyKey ?? newM3IdempotencyKey("m3-command"),
    );
  }

  let response: Response;
  try {
    response = await fetch(input.path, {
      ...(method === "GET" ? {} : { body: JSON.stringify(input.body) }),
      cache: "no-store",
      headers,
      method,
    });
  } catch {
    throw new M3ApiError({ code: "offline", correlationId, status: 0 });
  }

  const responseCorrelationId =
    response.headers.get("x-correlation-id") ?? correlationId;
  if (response.ok && response.status === 204) {
    return undefined as T;
  }
  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    throw new M3ApiError({
      code: "service_unavailable",
      correlationId: responseCorrelationId,
      status: response.status,
    });
  }
  const envelope = record(payload);
  if (!response.ok) {
    const error = record(envelope?.error);
    throw new M3ApiError({
      code: safeErrorCode(error?.code, response.status),
      correlationId: responseCorrelationId,
      status: response.status,
    });
  }
  if (!envelope || !("data" in envelope)) {
    throw new M3ApiError({
      code: "service_unavailable",
      correlationId: responseCorrelationId,
      status: response.status,
    });
  }
  return envelope.data as T;
}
