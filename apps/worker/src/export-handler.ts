import { generateExportArtifact, type ExportFormat } from "@vynlo/exports";

import {
  compileAuthorizedExportDefinition,
  readAuthorizedExportRows,
  type ExportExecutionSource,
  type ExportSourceReader,
} from "./export-source-registry";
import type { ImmutableArtifactStorage } from "./immutable-artifact-storage";
import type { ClaimedJob } from "./job-store";
import { JobExecutionError, type JobHandler } from "./job-runner";
import {
  assertExactKeys,
  CHECKSUM_PATTERN,
  m4Failure,
  requireRecord,
  requireUuid,
  UUID_PATTERN,
} from "./m4-worker-validation";

export const EXPORT_GENERATION_JOB_TYPE = "exports.generate" as const;

export interface ExportGenerationJobPayload {
  readonly columnPlanChecksum: string;
  readonly exportRunId: string;
  readonly exportVersionId: string;
  readonly filtersChecksum: string;
  readonly format: ExportFormat;
  readonly locale: string;
  readonly sortPlanChecksum: string;
  readonly sourceKey: string;
}

export interface ExportCompletionReplay {
  readonly artifactChecksum: string;
  readonly byteSize: number;
  readonly exportFileId: string;
  readonly rowCount: number;
}

export interface ExportRunRepository extends ExportSourceReader {
  complete(input: {
    readonly artifactChecksum: string;
    readonly byteSize: number;
    readonly correlationId: string;
    readonly exportRunId: string;
    readonly filename: string;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly mimeType: string;
    readonly objectPath: string;
    readonly receipt: Readonly<Record<string, unknown>>;
    readonly requestId: string;
    readonly rowCount: number;
    readonly signal: AbortSignal;
    readonly storageBucket: string;
    readonly storageGeneration: string;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<{
    readonly exportFileId: string;
    readonly replayed: boolean;
    readonly rowCount: number;
  }>;
  load(input: {
    readonly exportRunId: string;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly signal: AbortSignal;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<
    ExportExecutionSource &
      Readonly<{
        readonly completion: ExportCompletionReplay | null;
        readonly exportRunId: string;
      }>
  >;
  recordFailure(input: {
    readonly classification: JobExecutionError["classification"];
    readonly correlationId: string;
    readonly errorCode: string;
    readonly errorDetailSafe: string;
    readonly exportRunId: string;
    readonly jobId: string;
    readonly leaseToken: string;
    readonly requestId: string;
    readonly retryAfterSeconds?: number | undefined;
    readonly signal: AbortSignal;
    readonly workerId: string;
    readonly workspaceId: string;
  }): Promise<void>;
}

function invalidPayload(): never {
  throw new JobExecutionError({
    classification: "permanent",
    code: "export.invalid_job_payload",
    safeDetail: "The export generation job payload failed strict validation.",
  });
}

export function parseExportGenerationJobPayload(
  job: ClaimedJob,
): ExportGenerationJobPayload {
  const payload = requireRecord(job.payload, "export", "job_payload");
  assertExactKeys(
    payload,
    [
      "column_plan_checksum",
      "export_run_id",
      "export_version_id",
      "filters_checksum",
      "format",
      "locale",
      "sort_plan_checksum",
      "source_key",
    ],
    "export",
    "job_payload_keys",
  );
  const locale = payload.locale;
  const sourceKey = payload.source_key;
  if (
    job.jobType !== EXPORT_GENERATION_JOB_TYPE ||
    job.entityType !== "export_run" ||
    job.entityId === null ||
    job.payloadSchemaVersion !== 1 ||
    (payload.format !== "csv" && payload.format !== "xlsx") ||
    typeof locale !== "string" ||
    !/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/u.test(locale) ||
    typeof sourceKey !== "string" ||
    !/^[a-z][a-z0-9_]{0,95}$/u.test(sourceKey) ||
    typeof payload.filters_checksum !== "string" ||
    !CHECKSUM_PATTERN.test(payload.filters_checksum) ||
    typeof payload.column_plan_checksum !== "string" ||
    !CHECKSUM_PATTERN.test(payload.column_plan_checksum) ||
    typeof payload.sort_plan_checksum !== "string" ||
    !CHECKSUM_PATTERN.test(payload.sort_plan_checksum)
  ) {
    invalidPayload();
  }
  const exportRunId = requireUuid(
    payload.export_run_id,
    "export",
    "job_export_run_id",
  );
  if (exportRunId !== job.entityId) invalidPayload();
  return Object.freeze({
    columnPlanChecksum: payload.column_plan_checksum,
    exportRunId,
    exportVersionId: requireUuid(
      payload.export_version_id,
      "export",
      "job_export_version_id",
    ),
    filtersChecksum: payload.filters_checksum,
    format: payload.format,
    locale,
    sortPlanChecksum: payload.sort_plan_checksum,
    sourceKey,
  });
}

function exportStoragePath(input: {
  readonly checksum: string;
  readonly exportRunId: string;
  readonly format: ExportFormat;
  readonly workspaceId: string;
}): string {
  if (
    !CHECKSUM_PATTERN.test(input.checksum) ||
    !UUID_PATTERN.test(input.exportRunId) ||
    !UUID_PATTERN.test(input.workspaceId)
  ) {
    throw new TypeError("Invalid export storage path input.");
  }
  return `${input.workspaceId}/exports/${input.exportRunId}/v1/${input.checksum}.${input.format}`;
}

function assertSourceMatchesPayload(
  source: ExportExecutionSource & Readonly<{ readonly exportRunId: string }>,
  payload: ExportGenerationJobPayload,
): void {
  if (
    source.exportRunId !== payload.exportRunId ||
    source.sourceKey !== payload.sourceKey ||
    source.requestedFormat !== payload.format ||
    source.locale !== payload.locale
  ) {
    throw new JobExecutionError({
      classification: "validation",
      code: "export.run_snapshot_mismatch",
      safeDetail: "The export job differs from its immutable authorized run.",
    });
  }
}

export function createExportGenerationJobHandler(input: {
  readonly exports: ExportRunRepository;
  readonly storage: ImmutableArtifactStorage;
  readonly workerId: string;
}): JobHandler {
  return async (job, context) => {
    const failureRunId =
      job.entityId !== null && UUID_PATTERN.test(job.entityId)
        ? job.entityId
        : undefined;
    try {
      const payload = parseExportGenerationJobPayload(job);
      const source = await input.exports.load({
        exportRunId: payload.exportRunId,
        jobId: job.jobId,
        leaseToken: job.leaseToken,
        signal: context.signal,
        workerId: input.workerId,
        workspaceId: job.workspaceId,
      });
      assertSourceMatchesPayload(source, payload);
      if (source.completion !== null) {
        return {
          summary: {
            artifact_checksum: source.completion.artifactChecksum,
            byte_size: source.completion.byteSize,
            export_file_id: source.completion.exportFileId,
            export_run_id: payload.exportRunId,
            format: payload.format,
            replayed: true,
            row_count: source.completion.rowCount,
          },
        };
      }
      const definition = compileAuthorizedExportDefinition(source);
      const authorizedRows = await readAuthorizedExportRows({
        definition,
        exportRunId: payload.exportRunId,
        jobId: job.jobId,
        leaseToken: job.leaseToken,
        reader: input.exports,
        signal: context.signal,
        source,
        workerId: input.workerId,
        workspaceId: job.workspaceId,
      });
      const artifact = generateExportArtifact({
        authorization: {
          grantedPermissions: [
            "exports.run",
            "exports.run_sensitive",
            "reports.read",
            "inventory.read_internal",
          ],
          now: source.expiresAt,
          strongAuthAt: source.expiresAt,
        },
        definition,
        format: source.requestedFormat,
        locale: source.locale,
        rows: authorizedRows.rows,
      });
      const objectPath = exportStoragePath({
        checksum: artifact.checksum,
        exportRunId: payload.exportRunId,
        format: artifact.format,
        workspaceId: job.workspaceId,
      });
      const stored = await input.storage.put({
        body: artifact.bytes,
        checksum: artifact.checksum,
        contentType: artifact.contentType,
        objectPath,
        signal: context.signal,
      });
      if (
        stored.byteSize !== artifact.byteCount ||
        stored.checksum !== artifact.checksum ||
        stored.contentType !== artifact.contentType ||
        stored.objectPath !== objectPath
      ) {
        throw new JobExecutionError({
          classification: "permanent",
          code: "export.storage_receipt_mismatch",
          safeDetail:
            "Private export storage returned inconsistent provenance.",
        });
      }
      const receipt = Object.freeze({
        columnPlanChecksum: payload.columnPlanChecksum,
        exportVersionId: payload.exportVersionId,
        filtersChecksum: payload.filtersChecksum,
        sortPlanChecksum: payload.sortPlanChecksum,
        sourceSnapshotCapturedAt: authorizedRows.snapshot.capturedAt,
        sourceSnapshotFingerprint: authorizedRows.snapshot.fingerprint,
        sourceSnapshotId: authorizedRows.snapshot.id,
        sourceSnapshotRowCount: authorizedRows.snapshot.rowCount,
        storage: Object.freeze({
          bucket: stored.bucket,
          byteSize: stored.byteSize,
          checksumSha256: stored.checksum,
          generation: stored.generation,
          objectKey: stored.objectPath,
        }),
      });
      const completion = await input.exports.complete({
        artifactChecksum: artifact.checksum,
        byteSize: artifact.byteCount,
        correlationId: job.correlationId,
        exportRunId: payload.exportRunId,
        filename: `${source.definitionKey}-${payload.exportRunId}.${artifact.extension}`,
        jobId: job.jobId,
        leaseToken: job.leaseToken,
        mimeType: artifact.contentType,
        objectPath,
        receipt,
        requestId: `job:${job.jobId}:complete`,
        rowCount: artifact.rowCount,
        signal: context.signal,
        storageBucket: stored.bucket,
        storageGeneration: stored.generation,
        workerId: input.workerId,
        workspaceId: job.workspaceId,
      });
      return {
        summary: {
          artifact_checksum: artifact.checksum,
          byte_size: artifact.byteCount,
          export_file_id: completion.exportFileId,
          export_run_id: payload.exportRunId,
          format: artifact.format,
          replayed: completion.replayed,
          row_count: completion.rowCount,
        },
      };
    } catch (error) {
      const failure = m4Failure("export", error);
      if (failureRunId !== undefined && !context.signal.aborted) {
        try {
          await input.exports.recordFailure({
            classification: failure.classification,
            correlationId: job.correlationId,
            errorCode: failure.code,
            errorDetailSafe: failure.safeDetail,
            exportRunId: failureRunId,
            jobId: job.jobId,
            leaseToken: job.leaseToken,
            requestId: `job:${job.jobId}:failure`,
            retryAfterSeconds: failure.retryAfterSeconds,
            signal: context.signal,
            workerId: input.workerId,
            workspaceId: job.workspaceId,
          });
        } catch {
          // DurableJobRunner still receives and settles the original failure.
        }
      }
      throw failure;
    }
  };
}
