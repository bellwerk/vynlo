import {
  VinDecoderError,
  type JsonValue,
  type VinDecodedFacts,
  type VinDecoderPort,
} from "@vynlo/integrations";

import type { ClaimedJob } from "./job-store";
import { JobExecutionError, type JobHandler } from "./job-runner";

export const VIN_DECODE_JOB_TYPE = "inventory.vin_decode" as const;

export interface VinDecodeJobPayload {
  readonly modelYearHint: number | null;
  readonly requestId: string;
  readonly vin: string;
}

export interface VinDecodeCompletion {
  readonly aggregateVersion: number;
  readonly auditEventId: string;
  readonly decodeStatus: "succeeded";
  readonly duplicateCandidateCount: number;
  readonly outboxEventId: string;
  readonly replayed: boolean;
  readonly vinDecodeResultId: string;
}

export interface VinDecodeResultRepository {
  completeResult(input: {
    readonly correlationId: string;
    readonly decodedAt: string;
    readonly facts: VinDecodedFacts;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly providerKey: "nhtsa_vpic";
    readonly providerVersion: string;
    readonly rawResponse: JsonValue;
    readonly requestId: string;
    readonly signal: AbortSignal;
    readonly vinDecodeRequestId: string;
    readonly warnings: readonly string[];
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<VinDecodeCompletion>;
}

function invalidPayload(): JobExecutionError {
  return new JobExecutionError({
    classification: "validation",
    code: "vin.invalid_job_payload",
    safeDetail: "The VIN job payload failed strict contract validation.",
  });
}

export function parseVinDecodeJobPayload(job: ClaimedJob): VinDecodeJobPayload {
  const keys = Object.keys(job.payload).sort();
  const requestId = job.payload.request_id;
  const vin = job.payload.vin;
  const modelYearHint = job.payload.model_year_hint;
  if (
    job.jobType !== VIN_DECODE_JOB_TYPE ||
    job.entityType !== "vin_decode_request" ||
    job.payloadSchemaVersion !== 1 ||
    keys.join(",") !== "model_year_hint,request_id,vin" ||
    typeof requestId !== "string" ||
    requestId !== job.entityId ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(
      requestId,
    ) ||
    typeof vin !== "string" ||
    !/^[A-HJ-NPR-Z0-9]{17}$/u.test(vin) ||
    !(
      modelYearHint === null ||
      (Number.isInteger(modelYearHint) &&
        (modelYearHint as number) >= 1886 &&
        (modelYearHint as number) <= 2200)
    )
  ) {
    throw invalidPayload();
  }
  return {
    modelYearHint: modelYearHint as number | null,
    requestId: requestId.toLowerCase(),
    vin,
  };
}

function mapDecoderError(error: VinDecoderError): JobExecutionError {
  switch (error.code) {
    case "provider_rate_limited":
      return new JobExecutionError({
        classification: "rate_limited",
        code: "vin.provider_rate_limited",
        retryAfterSeconds:
          error.retryAfterMs === null
            ? undefined
            : Math.min(
                86_400,
                Math.max(1, Math.ceil(error.retryAfterMs / 1_000)),
              ),
        safeDetail: "The VIN provider requested a bounded retry delay.",
      });
    case "provider_unavailable":
      return new JobExecutionError({
        classification: "transient",
        code: "vin.provider_unavailable",
        safeDetail: "The VIN provider is temporarily unavailable.",
      });
    case "provider_aborted":
      return new JobExecutionError({
        classification: "transient",
        code: "vin.provider_aborted",
        safeDetail: "The VIN provider request ended before completion.",
      });
    case "invalid_vin":
    case "invalid_model_year":
      return new JobExecutionError({
        classification: "validation",
        code: `vin.${error.code}`,
        safeDetail: "The persisted VIN provider input is invalid.",
      });
    case "provider_rejected":
      return new JobExecutionError({
        classification: "permanent",
        code: "vin.provider_rejected",
        safeDetail: "The VIN provider rejected the validated request.",
      });
    case "provider_response_invalid":
    case "provider_response_too_large":
      return new JobExecutionError({
        classification: "permanent",
        code: `vin.${error.code}`,
        safeDetail: "The VIN provider returned an unusable bounded response.",
      });
  }

  return new JobExecutionError({
    classification: "unknown",
    code: "vin.unclassified_provider_failure",
    safeDetail: "The VIN provider failed without a recognized classification.",
  });
}

export function createVinDecodeJobHandler(input: {
  readonly decoder: VinDecoderPort;
  readonly repository: VinDecodeResultRepository;
  readonly workerId: string;
}): JobHandler {
  if (
    input.workerId.trim().length === 0 ||
    input.workerId.length > 200 ||
    !/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/u.test(input.workerId)
  ) {
    throw new TypeError(
      "VIN worker ID must be a stable non-secret identifier.",
    );
  }

  return async (job, context) => {
    const payload = parseVinDecodeJobPayload(job);
    let decoded;
    try {
      decoded = await input.decoder.decode({
        modelYear: payload.modelYearHint,
        signal: context.signal,
        vin: payload.vin,
      });
    } catch (error) {
      if (error instanceof VinDecoderError) {
        throw mapDecoderError(error);
      }
      throw error;
    }

    const completion = await input.repository.completeResult({
      correlationId: job.correlationId,
      decodedAt: decoded.decodedAt,
      facts: decoded.facts,
      jobId: job.jobId,
      leaseToken: job.leaseToken,
      providerKey: decoded.providerKey,
      providerVersion: decoded.providerVersion,
      rawResponse: decoded.rawResponse,
      requestId: `job:${job.jobId}`,
      signal: context.signal,
      vinDecodeRequestId: payload.requestId,
      warnings: decoded.warnings,
      workerId: input.workerId,
      workspaceId: job.workspaceId,
    });

    return {
      summary: {
        aggregate_version: completion.aggregateVersion,
        decode_status: completion.decodeStatus,
        duplicate_candidate_count: completion.duplicateCandidateCount,
        provider_key: decoded.providerKey,
        provider_version: decoded.providerVersion,
        replayed: completion.replayed,
        vin_decode_result_id: completion.vinDecodeResultId,
      },
    };
  };
}
