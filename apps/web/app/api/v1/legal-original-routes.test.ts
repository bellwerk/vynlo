import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { POST as createIntent } from "./documents/[id]/original-upload-intents/route";
import { POST as requestVerification } from "./documents/[id]/original-upload-completions/route";
import { GET as getUploadStatus } from "./documents/[id]/original-upload-sessions/[uploadSessionId]/route";
import { POST as retryVerification } from "./documents/[id]/original-upload-sessions/[uploadSessionId]/retry/route";

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
const publicKey = "sb_publishable_public_project_key_material_0001";

function command(path: string, body: unknown) {
  return new Request(`http://localhost${path}`, {
    body: JSON.stringify(body),
    headers: {
      Authorization: "Bearer user-header.user-payload.user-signature",
      "Content-Type": "application/json",
      "Idempotency-Key": "legal-original-route-001",
      "X-Correlation-Id": ids.correlation,
      "X-Request-Id": "request-legal-original-route-001",
      "X-Workspace-Id": ids.workspace,
    },
    method: "POST",
  });
}

function query(path: string) {
  return new Request(`http://localhost${path}`, {
    headers: {
      Authorization: "Bearer user-header.user-payload.user-signature",
      "X-Correlation-Id": ids.correlation,
      "X-Request-Id": "request-legal-original-status-001",
      "X-Workspace-Id": ids.workspace,
    },
  });
}

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", publicKey);
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("T-MED-002 / T-MED-003 / T-API-001 document original upload routes", () => {
  it("creates an exact intent then queues server verification", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
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
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            audit_event_id: ids.audit,
            document_id: ids.document,
            job_id: ids.job,
            job_status: "queued",
            outbox_event_id: ids.outbox,
            replayed: false,
            upload_session_id: ids.session,
          },
        ]),
      );
    vi.stubGlobal("fetch", fetchImplementation);
    const created = await createIntent(
      command(`/api/v1/documents/${ids.document}/original-upload-intents`, {
        byteSize: 1_000,
        checksumSha256: "a".repeat(64),
        filename: "registration.pdf",
        mediaKind: "legal_document",
        mimeType: "application/pdf",
      }),
      { params: Promise.resolve({ id: ids.document }) },
    );
    expect(created.status).toBe(201);
    const queued = await requestVerification(
      command(`/api/v1/documents/${ids.document}/original-upload-completions`, {
        uploadSessionId: ids.session,
      }),
      { params: Promise.resolve({ id: ids.document }) },
    );
    expect(queued.status).toBe(202);
    expect(fetchImplementation.mock.calls.map(([url]) => String(url))).toEqual([
      "http://127.0.0.1:54321/rest/v1/rpc/create_legal_original_upload_session",
      "http://127.0.0.1:54321/rest/v1/rpc/request_legal_original_upload_verification",
    ]);
    const secondBody = JSON.parse(
      String(fetchImplementation.mock.calls[1]?.[1]?.body),
    ) as Record<string, unknown>;
    expect(secondBody).toMatchObject({
      p_document_id: ids.document,
      p_upload_session_id: ids.session,
    });
    expect(secondBody).not.toHaveProperty("p_checksum_sha256");
  });

  it("maps owner-safe status and reasoned dead-letter retry RPCs", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
          {
            attempt_count: 6,
            completed_at: null,
            document_id: ids.document,
            error_classification: "transient",
            error_code: "media.storage_temporarily_unavailable",
            job_id: ids.sourceJob,
            maximum_attempts: 6,
            media_kind: "legal_document",
            retry_at: null,
            retryable: true,
            status: "dead_letter",
            upload_session_id: ids.session,
          },
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
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
        ]),
      );
    vi.stubGlobal("fetch", fetchImplementation);
    const params = Promise.resolve({
      id: ids.document,
      uploadSessionId: ids.session,
    });
    const status = await getUploadStatus(
      query(
        `/api/v1/documents/${ids.document}/original-upload-sessions/${ids.session}`,
      ),
      { params },
    );
    expect(status.status).toBe(200);
    await expect(status.json()).resolves.toMatchObject({
      data: {
        failure: { classification: "transient" },
        retryable: true,
        status: "dead_letter",
      },
    });

    const retry = await retryVerification(
      command(
        `/api/v1/documents/${ids.document}/original-upload-sessions/${ids.session}/retry`,
        { reason: "Operator confirmed the source remains available." },
      ),
      {
        params: Promise.resolve({
          id: ids.document,
          uploadSessionId: ids.session,
        }),
      },
    );
    expect(retry.status).toBe(202);
    expect(fetchImplementation.mock.calls.map(([url]) => String(url))).toEqual([
      "http://127.0.0.1:54321/rest/v1/rpc/get_legal_original_upload_status",
      "http://127.0.0.1:54321/rest/v1/rpc/retry_legal_original_upload_verification",
    ]);
    const retryBody = JSON.parse(
      String(fetchImplementation.mock.calls[1]?.[1]?.body),
    ) as Record<string, unknown>;
    expect(retryBody).toMatchObject({
      p_document_id: ids.document,
      p_reason: "Operator confirmed the source remains available.",
      p_upload_session_id: ids.session,
    });
    expect(retryBody).not.toHaveProperty("p_storage_object_key");
  });
});
