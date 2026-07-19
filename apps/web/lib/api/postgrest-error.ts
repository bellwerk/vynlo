export type SafeApiErrorCode =
  | "authentication_required"
  | "permission_denied"
  | "conflict"
  | "invalid_request"
  | "not_found"
  | "rate_limited"
  | "unprocessable_command"
  | "service_unavailable";

export class PostgrestCommandError extends Error {
  readonly code: SafeApiErrorCode;
  readonly status: 400 | 401 | 403 | 404 | 409 | 422 | 429 | 503;

  constructor(
    code: SafeApiErrorCode,
    status: 400 | 401 | 403 | 404 | 409 | 422 | 429 | 503,
  ) {
    super("The command data store rejected the request.");
    this.name = "PostgrestCommandError";
    this.code = code;
    this.status = status;
  }
}
