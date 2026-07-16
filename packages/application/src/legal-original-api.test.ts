import { describe, expect, it, vi } from "vitest";

import type { AuthenticatedRpcGateway } from "./vertical-slice-api";
import {
  LegalOriginalApplicationService,
  LegalOriginalRpcContractError,
  LegalOriginalValidationError,
} from "./legal-original-api";

const ids = {
  audit: "11000000-0000-4000-8000-000000000001",
  correlation: "12000000-0000-4000-8000-000000000001",
  document: "13000000-0000-4000-8000-000000000001",
  job: "14000000-0000-4000-8000-000000000001",
  outbox: "15000000-0000-4000-8000-000000000001",
  session: "16000000-0000-4000-8000-000000000001",
  sourceJob: "17000000-0000-4000-8000-000000000001",
  workspace: "10000000-0000-4000-8000-000000000001",
} as const;

const metadata = {
  accessToken: "fixture-token",
  correlationId: ids.correlation,
  idempotencyKey: "legal-original-command-001",
  requestId: "request-legal-original-001",
  workspaceId: ids.workspace,
} as const;

describe("T-MED-002 / T-MED-003 / T-API-001 legal original application API", () => {
  it("forwards normalized intent metadata without issuing a client attestation", async () => {
    const invoke = vi
      .fn<AuthenticatedRpcGateway["invoke"]>()
      .mockResolvedValue([
        {
          audit_event_id: ids.audit,
          document_id: ids.document,
          expires_at: "2026-07-16T12:15:00.000Z",
          media_kind: "legal_document",
          replayed: false,
          upload_bucket: "media-private",
          upload_object_key: `workspaces/${ids.workspace}/documents/${ids.document}/upload-intents/${ids.session}/source`,
          upload_session_id: ids.session,
        },
      ]);
    const result = await new LegalOriginalApplicationService({
      invoke,
    }).createUploadIntent({
      body: {
        byteSize: 1_000,
        checksumSha256: "a".repeat(64),
        filename: " registration.pdf ",
        mediaKind: "legal_document",
        mimeType: "application/pdf",
      },
      documentId: ids.document,
      metadata,
    });
    expect(result.upload).toEqual({
      bucket: "media-private",
      objectKey: expect.stringContaining(ids.session),
    });
    expect(invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "create_legal_original_upload_session",
        parameters: expect.objectContaining({
          p_document_id: ids.document,
          p_expected_byte_size: 1_000,
          p_expected_checksum_sha256: "a".repeat(64),
          p_original_filename: "registration.pdf",
        }),
      }),
    );
  });

  it("requests verification with only the opaque upload session reference", async () => {
    const invoke = vi
      .fn<AuthenticatedRpcGateway["invoke"]>()
      .mockResolvedValue([
        {
          audit_event_id: ids.audit,
          document_id: ids.document,
          job_id: ids.job,
          job_status: "queued",
          outbox_event_id: ids.outbox,
          replayed: false,
          upload_session_id: ids.session,
        },
      ]);
    const result = await new LegalOriginalApplicationService({
      invoke,
    }).requestVerification({
      body: { uploadSessionId: ids.session },
      documentId: ids.document,
      metadata,
    });
    expect(result.job).toEqual({ id: ids.job, status: "queued" });
    expect(invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "request_legal_original_upload_verification",
        parameters: expect.objectContaining({
          p_document_id: ids.document,
          p_upload_session_id: ids.session,
        }),
      }),
    );
  });

  it("projects owner-safe dead-letter status without provider evidence", async () => {
    const invoke = vi
      .fn<AuthenticatedRpcGateway["invoke"]>()
      .mockResolvedValue([
        {
          attempt_count: 6,
          completed_at: null,
          document_id: ids.document,
          error_classification: "transient",
          error_code: "media.storage_temporarily_unavailable",
          job_id: ids.job,
          maximum_attempts: 6,
          media_kind: "legal_document",
          retry_at: null,
          retryable: true,
          status: "dead_letter",
          upload_session_id: ids.session,
        },
      ]);
    const result = await new LegalOriginalApplicationService({
      invoke,
    }).getUploadStatus({
      documentId: ids.document,
      metadata: {
        accessToken: metadata.accessToken,
        workspaceId: metadata.workspaceId,
      },
      uploadSessionId: ids.session,
    });
    expect(result).toMatchObject({
      documentId: ids.document,
      failure: {
        classification: "transient",
        code: "media.storage_temporarily_unavailable",
      },
      job: { attemptCount: 6, id: ids.job, maximumAttempts: 6 },
      retryable: true,
      status: "dead_letter",
      uploadSessionId: ids.session,
    });
    expect(invoke).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      functionName: "get_legal_original_upload_status",
      parameters: {
        p_document_id: ids.document,
        p_upload_session_id: ids.session,
        p_workspace_id: ids.workspace,
      },
    });
  });

  it("queues a reasoned retry of the exact dead-letter upload", async () => {
    const invoke = vi
      .fn<AuthenticatedRpcGateway["invoke"]>()
      .mockResolvedValue([
        {
          audit_event_id: ids.audit,
          document_id: ids.document,
          job_id: ids.job,
          job_status: "queued",
          outbox_event_id: ids.outbox,
          replayed: false,
          source_job_id: ids.sourceJob,
          upload_session_id: ids.session,
        },
      ]);
    const result = await new LegalOriginalApplicationService({
      invoke,
    }).retryVerification({
      body: { reason: " Operator confirmed the source remains available. " },
      documentId: ids.document,
      metadata,
      uploadSessionId: ids.session,
    });
    expect(result).toMatchObject({
      job: { id: ids.job, status: "queued" },
      replayed: false,
      sourceJobId: ids.sourceJob,
    });
    expect(invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "retry_legal_original_upload_verification",
        parameters: expect.objectContaining({
          p_document_id: ids.document,
          p_idempotency_key: metadata.idempotencyKey,
          p_reason: "Operator confirmed the source remains available.",
          p_upload_session_id: ids.session,
        }),
      }),
    );
  });

  it("rejects invalid input before RPC traffic", async () => {
    const invoke = vi.fn<AuthenticatedRpcGateway["invoke"]>();
    await expect(
      new LegalOriginalApplicationService({ invoke }).createUploadIntent({
        body: {
          byteSize: 50_000_001,
          checksumSha256: "a".repeat(64),
          filename: "oversized.pdf",
          mediaKind: "legal_document",
          mimeType: "application/pdf",
        },
        documentId: ids.document,
        metadata,
      }),
    ).rejects.toBeInstanceOf(LegalOriginalValidationError);
    expect(invoke).not.toHaveBeenCalled();
  });

  it("fails closed on malformed database rows", async () => {
    const invoke = vi
      .fn<AuthenticatedRpcGateway["invoke"]>()
      .mockResolvedValue([{ upload_session_id: ids.session }]);
    await expect(
      new LegalOriginalApplicationService({ invoke }).requestVerification({
        body: { uploadSessionId: ids.session },
        documentId: ids.document,
        metadata,
      }),
    ).rejects.toBeInstanceOf(LegalOriginalRpcContractError);
  });

  it("rejects inconsistent retry projections and empty retry reasons", async () => {
    const invoke = vi
      .fn<AuthenticatedRpcGateway["invoke"]>()
      .mockResolvedValue([
        {
          attempt_count: 0,
          completed_at: null,
          document_id: ids.document,
          error_classification: null,
          error_code: null,
          job_id: null,
          maximum_attempts: null,
          media_kind: "legal_document",
          retry_at: null,
          retryable: true,
          status: "queued",
          upload_session_id: ids.session,
        },
      ]);
    const service = new LegalOriginalApplicationService({ invoke });
    await expect(
      service.getUploadStatus({
        documentId: ids.document,
        metadata: {
          accessToken: metadata.accessToken,
          workspaceId: metadata.workspaceId,
        },
        uploadSessionId: ids.session,
      }),
    ).rejects.toBeInstanceOf(LegalOriginalRpcContractError);
    await expect(
      service.retryVerification({
        body: { reason: " " },
        documentId: ids.document,
        metadata,
        uploadSessionId: ids.session,
      }),
    ).rejects.toBeInstanceOf(LegalOriginalValidationError);
    expect(invoke).toHaveBeenCalledTimes(1);
  });
});
