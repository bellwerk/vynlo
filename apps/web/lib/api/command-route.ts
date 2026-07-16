import {
  type VerticalSliceApplicationService,
  type VerticalSliceCommandInput,
  type VerticalSliceCommandMetadata,
  VerticalSliceRpcContractError,
  VerticalSliceValidationError,
  WorkspaceInvitationRpcContractError,
  WorkspaceInvitationValidationError,
} from "@vynlo/application";
import { z } from "zod";
import {
  createVerticalSliceApplicationService,
  PostgrestCommandError,
} from "./postgrest";

export const MAX_COMMAND_BODY_BYTES = 32 * 1024;

type RequestErrorCode =
  | "authentication_required"
  | "invalid_workspace"
  | "invalid_idempotency_key"
  | "invalid_request_id"
  | "invalid_correlation_id"
  | "invalid_content_type"
  | "invalid_json"
  | "request_body_too_large";

class CommandRequestError extends Error {
  readonly code: RequestErrorCode;
  readonly status: 400 | 401;

  constructor(code: RequestErrorCode, status: 400 | 401 = 400) {
    super("The command request is invalid.");
    this.name = "CommandRequestError";
    this.code = code;
    this.status = status;
  }
}

const bearerTokenSchema = z
  .string()
  .max(8_192)
  .regex(/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/iu)
  .transform((value) => value.slice(value.indexOf(" ") + 1));
const uuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());
const idempotencyKeySchema = z
  .string()
  .min(8)
  .max(200)
  .regex(/^[\x21-\x7e]+$/u);
const requestIdSchema = z
  .string()
  .min(1)
  .max(128)
  .regex(/^[A-Za-z0-9][A-Za-z0-9._:-]*$/u);

function responseIdentifiers(request: Request): {
  readonly correlationId: string;
  readonly requestId: string;
} {
  const requestId = requestIdSchema.safeParse(
    request.headers.get("x-request-id"),
  );
  const correlationId = uuidSchema.safeParse(
    request.headers.get("x-correlation-id"),
  );
  return {
    correlationId: correlationId.success
      ? correlationId.data
      : crypto.randomUUID(),
    requestId: requestId.success ? requestId.data : crypto.randomUUID(),
  };
}

export function parseCommandMetadata(
  request: Request,
): VerticalSliceCommandMetadata {
  const authorization = bearerTokenSchema.safeParse(
    request.headers.get("authorization"),
  );
  if (!authorization.success) {
    throw new CommandRequestError("authentication_required", 401);
  }

  const workspaceId = uuidSchema.safeParse(
    request.headers.get("x-workspace-id"),
  );
  if (!workspaceId.success) {
    throw new CommandRequestError("invalid_workspace");
  }

  const idempotencyKey = idempotencyKeySchema.safeParse(
    request.headers.get("idempotency-key"),
  );
  if (!idempotencyKey.success) {
    throw new CommandRequestError("invalid_idempotency_key");
  }

  const requestId = requestIdSchema.safeParse(
    request.headers.get("x-request-id"),
  );
  if (!requestId.success) {
    throw new CommandRequestError("invalid_request_id");
  }

  const correlationId = uuidSchema.safeParse(
    request.headers.get("x-correlation-id"),
  );
  if (!correlationId.success) {
    throw new CommandRequestError("invalid_correlation_id");
  }

  return {
    accessToken: authorization.data,
    correlationId: correlationId.data,
    idempotencyKey: idempotencyKey.data,
    requestId: requestId.data,
    workspaceId: workspaceId.data,
  };
}

function validateDeclaredLength(request: Request): void {
  const value = request.headers.get("content-length");
  if (value === null) {
    return;
  }
  if (!/^\d+$/u.test(value) || Number(value) > MAX_COMMAND_BODY_BYTES) {
    throw new CommandRequestError("request_body_too_large");
  }
}

export async function readCommandJson(request: Request): Promise<unknown> {
  const mediaType = request.headers
    .get("content-type")
    ?.split(";", 1)[0]
    ?.trim()
    .toLowerCase();
  if (mediaType !== "application/json") {
    throw new CommandRequestError("invalid_content_type");
  }
  validateDeclaredLength(request);

  if (!request.body) {
    throw new CommandRequestError("invalid_json");
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  while (true) {
    const next = await reader.read();
    if (next.done) {
      break;
    }
    totalBytes += next.value.byteLength;
    if (totalBytes > MAX_COMMAND_BODY_BYTES) {
      await reader.cancel();
      throw new CommandRequestError("request_body_too_large");
    }
    chunks.push(next.value);
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    if (text.trim() === "") {
      throw new CommandRequestError("invalid_json");
    }
    const body: unknown = JSON.parse(text);
    return body;
  } catch (error) {
    if (error instanceof CommandRequestError) {
      throw error;
    }
    throw new CommandRequestError("invalid_json");
  }
}

const safeMessages: Readonly<Record<string, string>> = Object.freeze({
  authentication_required: "A valid bearer session is required.",
  conflict: "The command conflicts with current state.",
  invalid_content_type: "The request must contain JSON.",
  invalid_correlation_id: "The correlation identifier is invalid.",
  invalid_idempotency_key: "The idempotency key is invalid.",
  invalid_json: "The JSON request body is invalid.",
  invalid_request: "The request is invalid.",
  invalid_request_body: "The command body is invalid.",
  invalid_request_id: "The request identifier is invalid.",
  invalid_workspace: "The workspace selection is invalid.",
  permission_denied: "The command is not permitted.",
  rate_limited: "The command service is temporarily rate limited.",
  request_body_too_large: "The command body exceeds the allowed size.",
  service_unavailable: "The command service is temporarily unavailable.",
  unprocessable_command: "The command cannot be applied to current state.",
});

function responseHeaders(request: Request): HeadersInit {
  const identifiers = responseIdentifiers(request);
  return {
    "Cache-Control": "no-store",
    "X-Correlation-Id": identifiers.correlationId,
    "X-Request-Id": identifiers.requestId,
  };
}

function errorResponse(
  request: Request,
  code: string,
  status: number,
): Response {
  return Response.json(
    {
      error: {
        code,
        message:
          safeMessages[code] ??
          (status === 422
            ? "The command body is invalid."
            : "The command service is temporarily unavailable."),
      },
    },
    { headers: responseHeaders(request), status },
  );
}

function mapError(request: Request, error: unknown): Response {
  if (error instanceof CommandRequestError) {
    return errorResponse(request, error.code, error.status);
  }
  if (error instanceof VerticalSliceValidationError) {
    return errorResponse(request, error.code, 422);
  }
  if (error instanceof WorkspaceInvitationValidationError) {
    return errorResponse(request, error.code, 422);
  }
  if (error instanceof PostgrestCommandError) {
    return errorResponse(request, error.code, error.status);
  }
  if (
    error instanceof VerticalSliceRpcContractError ||
    error instanceof WorkspaceInvitationRpcContractError
  ) {
    return errorResponse(request, "service_unavailable", 503);
  }
  return errorResponse(request, "service_unavailable", 503);
}

export interface CommandRouteOptions<TResult> {
  readonly execute: (
    service: VerticalSliceApplicationService,
    input: VerticalSliceCommandInput,
  ) => Promise<TResult>;
  readonly successStatus: (result: TResult) => 200 | 201 | 202;
}

export interface ApplicationCommandRouteOptions<TService, TResult> {
  readonly createService: () => TService;
  readonly execute: (
    service: TService,
    input: VerticalSliceCommandInput,
  ) => Promise<TResult>;
  readonly successStatus: (result: TResult) => 200 | 201 | 202;
}

export async function handleApplicationCommandRoute<TService, TResult>(
  request: Request,
  options: ApplicationCommandRouteOptions<TService, TResult>,
): Promise<Response> {
  try {
    const metadata = parseCommandMetadata(request);
    const body = await readCommandJson(request);
    const result = await options.execute(options.createService(), {
      body,
      metadata,
    });
    return Response.json(
      { data: result },
      {
        headers: responseHeaders(request),
        status: options.successStatus(result),
      },
    );
  } catch (error) {
    return mapError(request, error);
  }
}

export async function handleCommandRoute<TResult>(
  request: Request,
  options: CommandRouteOptions<TResult>,
): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createVerticalSliceApplicationService,
    execute: options.execute,
    successStatus: options.successStatus,
  });
}
