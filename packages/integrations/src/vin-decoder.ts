const VIN_PATTERN = /^[A-HJ-NPR-Z0-9]{17}$/u;
const DEFAULT_ENDPOINT =
  "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues";
const DEFAULT_TIMEOUT_MS = 8_000;
const DEFAULT_MAX_RESPONSE_BYTES = 1_000_000;
const MAX_RETRY_AFTER_MS = 86_400_000;

export type JsonPrimitive = boolean | number | string | null;
export type JsonValue =
  JsonPrimitive | readonly JsonValue[] | { readonly [key: string]: JsonValue };

export interface VinDecodedFacts {
  readonly bodyType: string | null;
  readonly cylinders: number | null;
  readonly drivetrain: string | null;
  readonly engineLiters: string | null;
  readonly fuelType: string | null;
  readonly horsepower: number | null;
  readonly make: string | null;
  readonly model: string | null;
  readonly modelYear: number | null;
  readonly transmission: string | null;
  readonly trim: string | null;
}

export interface VinDecodeRequest {
  readonly modelYear?: number | null;
  readonly signal?: AbortSignal;
  readonly vin: string;
}

export interface VinDecodeResult {
  readonly decodedAt: string;
  readonly facts: VinDecodedFacts;
  readonly providerKey: "nhtsa_vpic";
  readonly providerVersion: string;
  readonly rawResponse: JsonValue;
  readonly vin: string;
  readonly warnings: readonly string[];
}

export interface VinDecoderPort {
  decode(request: VinDecodeRequest): Promise<VinDecodeResult>;
}

export type VinDecoderErrorCode =
  | "invalid_vin"
  | "invalid_model_year"
  | "provider_aborted"
  | "provider_rate_limited"
  | "provider_rejected"
  | "provider_unavailable"
  | "provider_response_too_large"
  | "provider_response_invalid";

export class VinDecoderError extends Error {
  readonly code: VinDecoderErrorCode;
  readonly retryAfterMs: number | null;
  readonly retryable: boolean;

  constructor(
    code: VinDecoderErrorCode,
    options: Readonly<{
      cause?: unknown;
      retryAfterMs?: number | null;
      retryable: boolean;
    }>,
  ) {
    super("The VIN decoder could not complete the request.", {
      cause: options.cause,
    });
    this.name = "VinDecoderError";
    this.code = code;
    this.retryAfterMs = options.retryAfterMs ?? null;
    this.retryable = options.retryable;
  }
}

export interface NhtsaVpicVinDecoderOptions {
  readonly endpoint?: string;
  readonly fetchImplementation?: typeof fetch;
  readonly maxResponseBytes?: number;
  readonly now?: () => Date;
  readonly providerVersion?: string;
  readonly timeoutMs?: number;
}

function normalizeVin(vin: string): string {
  const normalized = vin.trim().toUpperCase();
  if (!VIN_PATTERN.test(normalized)) {
    throw new VinDecoderError("invalid_vin", { retryable: false });
  }
  return normalized;
}

function validateModelYear(value: number | null | undefined): number | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (!Number.isInteger(value) || value < 1886 || value > 2200) {
    throw new VinDecoderError("invalid_model_year", { retryable: false });
  }
  return value;
}

function validateEndpoint(value: string): URL {
  let endpoint: URL;
  try {
    endpoint = new URL(value);
  } catch (cause) {
    throw new TypeError("VIN decoder endpoint must be an absolute URL.", {
      cause,
    });
  }
  if (
    endpoint.protocol !== "https:" ||
    endpoint.username !== "" ||
    endpoint.password !== "" ||
    endpoint.hash !== ""
  ) {
    throw new TypeError(
      "VIN decoder endpoint must be an HTTPS URL without credentials or a fragment.",
    );
  }
  return endpoint;
}

function positiveInteger(value: number, label: string): number {
  if (!Number.isInteger(value) || value < 1) {
    throw new TypeError(`${label} must be a positive integer.`);
  }
  return value;
}

function object(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function isJsonValue(value: unknown): value is JsonValue {
  if (
    value === null ||
    typeof value === "boolean" ||
    typeof value === "string"
  ) {
    return true;
  }
  if (typeof value === "number") {
    return Number.isFinite(value);
  }
  if (Array.isArray(value)) {
    return value.every(isJsonValue);
  }
  const source = object(value);
  return source !== null && Object.values(source).every(isJsonValue);
}

function textValue(
  source: Record<string, unknown>,
  key: string,
): string | null {
  const value = source[key];
  if (typeof value !== "string") {
    return null;
  }
  const normalized = value.trim();
  return normalized === "" ||
    normalized.toLowerCase() === "not applicable" ||
    normalized.toLowerCase() === "null"
    ? null
    : normalized;
}

function integerValue(
  source: Record<string, unknown>,
  key: string,
): number | null {
  const value = textValue(source, key);
  if (value === null || !/^\d+$/u.test(value)) {
    return null;
  }
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function decimalValue(
  source: Record<string, unknown>,
  key: string,
): string | null {
  const value = textValue(source, key);
  if (value === null || !/^\d+(?:\.\d+)?$/u.test(value)) {
    return null;
  }
  return value;
}

function parseWarnings(source: Record<string, unknown>): readonly string[] {
  const errorCode = textValue(source, "ErrorCode");
  const errorText = textValue(source, "ErrorText");
  if (errorCode === null || errorCode === "0") {
    return errorText === null ? [] : [errorText];
  }
  return [
    `vpic_error_code:${errorCode}`,
    ...(errorText === null ? [] : [errorText]),
  ];
}

function parseVpicResponse(payload: unknown): Readonly<{
  facts: VinDecodedFacts;
  rawResponse: JsonValue;
  warnings: readonly string[];
}> {
  if (!isJsonValue(payload)) {
    throw new VinDecoderError("provider_response_invalid", {
      retryable: false,
    });
  }
  const root = object(payload);
  const results = root?.Results;
  const first = Array.isArray(results) ? object(results[0]) : null;
  if (!root || !first) {
    throw new VinDecoderError("provider_response_invalid", {
      retryable: false,
    });
  }

  return {
    facts: {
      bodyType: textValue(first, "BodyClass"),
      cylinders: integerValue(first, "EngineCylinders"),
      drivetrain: textValue(first, "DriveType"),
      engineLiters: decimalValue(first, "DisplacementL"),
      fuelType: textValue(first, "FuelTypePrimary"),
      horsepower: integerValue(first, "EngineHP"),
      make: textValue(first, "Make"),
      model: textValue(first, "Model"),
      modelYear: integerValue(first, "ModelYear"),
      transmission: textValue(first, "TransmissionStyle"),
      trim: textValue(first, "Trim"),
    },
    rawResponse: payload,
    warnings: parseWarnings(first),
  };
}

function parseRetryAfter(value: string | null, now: Date): number | null {
  if (value === null) {
    return null;
  }
  const normalized = value.trim();
  if (/^\d+$/u.test(normalized)) {
    const seconds = Number(normalized);
    return Number.isSafeInteger(seconds)
      ? Math.min(seconds * 1_000, MAX_RETRY_AFTER_MS)
      : MAX_RETRY_AFTER_MS;
  }
  const date = Date.parse(value);
  return Number.isFinite(date)
    ? Math.min(MAX_RETRY_AFTER_MS, Math.max(0, date - now.getTime()))
    : null;
}

async function readBoundedText(
  response: Response,
  maxResponseBytes: number,
  signal: AbortSignal,
): Promise<string> {
  const contentLength = response.headers.get("content-length");
  if (
    contentLength !== null &&
    /^\d+$/u.test(contentLength) &&
    Number(contentLength) > maxResponseBytes
  ) {
    throw new VinDecoderError("provider_response_too_large", {
      retryable: false,
    });
  }
  if (response.body === null) {
    return "";
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let byteLength = 0;
  let completed = false;
  let text = "";
  try {
    while (true) {
      const result = await new Promise<ReadableStreamReadResult<Uint8Array>>(
        (resolve, reject) => {
          const abort = () => {
            void reader.cancel(signal.reason).catch(() => undefined);
            reject(
              new DOMException(
                "The VIN provider response was aborted.",
                "AbortError",
              ),
            );
          };
          if (signal.aborted) {
            abort();
            return;
          }
          signal.addEventListener("abort", abort, { once: true });
          void reader
            .read()
            .then(resolve, reject)
            .finally(() => {
              signal.removeEventListener("abort", abort);
            });
        },
      );
      if (result.done) {
        completed = true;
        text += decoder.decode();
        return text;
      }
      byteLength += result.value.byteLength;
      if (byteLength > maxResponseBytes) {
        throw new VinDecoderError("provider_response_too_large", {
          retryable: false,
        });
      }
      text += decoder.decode(result.value, { stream: true });
    }
  } finally {
    if (!completed) {
      await reader.cancel().catch(() => undefined);
    }
    reader.releaseLock();
  }
}

export class NhtsaVpicVinDecoderAdapter implements VinDecoderPort {
  readonly #endpoint: URL;
  readonly #fetch: typeof fetch;
  readonly #maxResponseBytes: number;
  readonly #now: () => Date;
  readonly #providerVersion: string;
  readonly #timeoutMs: number;

  constructor(options: NhtsaVpicVinDecoderOptions = {}) {
    this.#endpoint = validateEndpoint(options.endpoint ?? DEFAULT_ENDPOINT);
    this.#fetch = options.fetchImplementation ?? fetch;
    this.#maxResponseBytes = positiveInteger(
      options.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES,
      "VIN decoder maximum response bytes",
    );
    this.#now = options.now ?? (() => new Date());
    this.#providerVersion = options.providerVersion ?? "vpic-api";
    this.#timeoutMs = positiveInteger(
      options.timeoutMs ?? DEFAULT_TIMEOUT_MS,
      "VIN decoder timeout",
    );
  }

  async decode(request: VinDecodeRequest): Promise<VinDecodeResult> {
    const vin = normalizeVin(request.vin);
    const modelYear = validateModelYear(request.modelYear);
    const url = new URL(
      `${this.#endpoint.toString().replace(/\/$/u, "")}/${encodeURIComponent(vin)}`,
    );
    url.searchParams.set("format", "json");
    if (modelYear !== null) {
      url.searchParams.set("modelyear", String(modelYear));
    }

    const controller = new AbortController();
    const abortFromCaller = () => controller.abort(request.signal?.reason);
    request.signal?.addEventListener("abort", abortFromCaller, { once: true });
    const timeout = setTimeout(
      () => controller.abort("timeout"),
      this.#timeoutMs,
    );

    try {
      const response = await this.#fetch(url, {
        headers: { Accept: "application/json" },
        method: "GET",
        redirect: "error",
        signal: controller.signal,
      });
      if (response.status === 429) {
        throw new VinDecoderError("provider_rate_limited", {
          retryAfterMs: parseRetryAfter(
            response.headers.get("retry-after"),
            this.#now(),
          ),
          retryable: true,
        });
      }
      if (response.status >= 500) {
        throw new VinDecoderError("provider_unavailable", { retryable: true });
      }
      if (!response.ok) {
        throw new VinDecoderError("provider_rejected", { retryable: false });
      }

      const text = await readBoundedText(
        response,
        this.#maxResponseBytes,
        controller.signal,
      );
      let payload: unknown;
      try {
        payload = JSON.parse(text) as unknown;
      } catch (cause) {
        throw new VinDecoderError("provider_response_invalid", {
          cause,
          retryable: false,
        });
      }
      const parsed = parseVpicResponse(payload);
      return {
        decodedAt: this.#now().toISOString(),
        facts: parsed.facts,
        providerKey: "nhtsa_vpic",
        providerVersion: this.#providerVersion,
        rawResponse: parsed.rawResponse,
        vin,
        warnings: parsed.warnings,
      };
    } catch (cause) {
      if (cause instanceof VinDecoderError) {
        throw cause;
      }
      if (controller.signal.aborted && request.signal?.aborted) {
        throw new VinDecoderError("provider_aborted", {
          cause,
          retryable: false,
        });
      }
      throw new VinDecoderError("provider_unavailable", {
        cause,
        retryable: true,
      });
    } finally {
      clearTimeout(timeout);
      request.signal?.removeEventListener("abort", abortFromCaller);
    }
  }
}
