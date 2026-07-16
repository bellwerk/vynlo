import { describe, expect, it, vi } from "vitest";

import type { AuthenticatedRpcGateway } from "./vertical-slice-api";
import {
  DocumentPreviewDownloadApplicationService,
  DocumentPreviewDownloadRpcContractError,
  DocumentPreviewDownloadValidationError,
  type DocumentPreviewDownloadGrantPort,
} from "./document-preview-download-api";

const ids = Object.freeze({
  artifact: "10000000-0000-4000-8000-000000000001",
  audit: "10000000-0000-4000-8000-000000000002",
  authorization: "10000000-0000-4000-8000-000000000003",
  correlation: "10000000-0000-4000-8000-000000000004",
  document: "10000000-0000-4000-8000-000000000005",
  workspace: "10000000-0000-4000-8000-000000000006",
});

const row = Object.freeze({
  artifact_id: ids.artifact,
  audit_event_id: ids.audit,
  authorization_expires_at: "2026-07-16T20:05:00.000Z",
  authorization_id: ids.authorization,
  byte_size: 512,
  checksum_sha256: "f".repeat(64),
  document_id: ids.document,
  filename: "preview.html" as const,
  mime_type: "text/html; charset=utf-8" as const,
  replayed: false,
});

function input(body: unknown = { expiresInSeconds: 60 }) {
  return {
    artifactId: ids.artifact,
    body,
    metadata: {
      accessToken: "header.payload.signature",
      correlationId: ids.correlation,
      idempotencyKey: "preview-download-001",
      requestId: "request-preview-download-001",
      workspaceId: ids.workspace,
    },
  } as const;
}

function setup(result: unknown = [row]) {
  const invoke = vi
    .fn<AuthenticatedRpcGateway["invoke"]>()
    .mockResolvedValue(result);
  const issue = vi
    .fn<DocumentPreviewDownloadGrantPort["issue"]>()
    .mockResolvedValue({
      expiresAt: "2026-07-16T20:01:00.000Z",
      url: "https://example.supabase.co/storage/v1/object/sign/preview-artifacts/signed",
    });
  return {
    invoke,
    issue,
    service: new DocumentPreviewDownloadApplicationService(
      { invoke },
      { issue },
    ),
  };
}

describe("T-DOC-001 / T-STOR-001 DocumentPreviewDownloadApplicationService", () => {
  it("authorizes one artifact and issues a server-side exact-file grant", async () => {
    const { invoke, issue, service } = setup();

    await expect(service.authorize(input())).resolves.toEqual({
      artifactId: ids.artifact,
      auditEventId: ids.audit,
      byteSize: 512,
      checksumSha256: "f".repeat(64),
      documentId: ids.document,
      download: {
        expiresAt: "2026-07-16T20:01:00.000Z",
        url: "https://example.supabase.co/storage/v1/object/sign/preview-artifacts/signed",
      },
      filename: "preview.html",
      mimeType: "text/html; charset=utf-8",
      replayed: false,
    });
    expect(invoke).toHaveBeenCalledWith({
      accessToken: "header.payload.signature",
      functionName: "authorize_document_preview_download",
      parameters: {
        p_artifact_id: ids.artifact,
        p_correlation_id: ids.correlation,
        p_expires_in_seconds: 60,
        p_idempotency_key: "preview-download-001",
        p_request_id: "request-preview-download-001",
        p_workspace_id: ids.workspace,
      },
    });
    expect(issue).toHaveBeenCalledWith({
      artifactId: ids.artifact,
      authorizationExpiresAt: "2026-07-16T20:05:00.000Z",
      authorizationId: ids.authorization,
      byteSize: 512,
      checksumSha256: "f".repeat(64),
      documentId: ids.document,
      expiresInSeconds: 60,
      filename: "preview.html",
      mimeType: "text/html; charset=utf-8",
      workspaceId: ids.workspace,
    });
  });

  it.each([
    ["invalid artifact", { ...input(), artifactId: "not-a-uuid" }],
    ["short expiry", input({ expiresInSeconds: 29 })],
    [
      "unknown field",
      input({ expiresInSeconds: 60, storageBucket: "preview-artifacts" }),
    ],
  ])("rejects %s before database access", async (_label, candidate) => {
    const { invoke, service } = setup();
    await expect(service.authorize(candidate)).rejects.toBeInstanceOf(
      DocumentPreviewDownloadValidationError,
    );
    expect(invoke).not.toHaveBeenCalled();
  });

  it("rejects a missing or extra authorization row", async () => {
    for (const result of [[], [row, row]]) {
      const { issue, service } = setup(result);
      await expect(service.authorize(input())).rejects.toBeInstanceOf(
        DocumentPreviewDownloadRpcContractError,
      );
      expect(issue).not.toHaveBeenCalled();
    }
  });

  it("rejects a response for a different artifact", async () => {
    const { issue, service } = setup([
      { ...row, artifact_id: "20000000-0000-4000-8000-000000000001" },
    ]);
    await expect(service.authorize(input())).rejects.toBeInstanceOf(
      DocumentPreviewDownloadRpcContractError,
    );
    expect(issue).not.toHaveBeenCalled();
  });

  it("rejects provider coordinates in the database response contract", async () => {
    const { issue, service } = setup([
      { ...row, storage_bucket: "preview-artifacts" },
    ]);
    await expect(service.authorize(input())).rejects.toBeInstanceOf(
      DocumentPreviewDownloadRpcContractError,
    );
    expect(issue).not.toHaveBeenCalled();
  });
});
