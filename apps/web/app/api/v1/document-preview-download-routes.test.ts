import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { POST as createPreviewDownloadGrant } from "./document-preview-artifacts/[id]/download-grants/route";

const ids = Object.freeze({
  artifact: "10000000-0000-4000-8000-000000000001",
  audit: "10000000-0000-4000-8000-000000000002",
  authorization: "10000000-0000-4000-8000-000000000003",
  correlation: "10000000-0000-4000-8000-000000000004",
  document: "10000000-0000-4000-8000-000000000005",
  workspace: "10000000-0000-4000-8000-000000000006",
});
const publicKey = "sb_publishable_public_project_key_material_0001";
const serviceRole = "server-service-role-must-never-reach-browser";

function command(body: unknown): Request {
  return new Request(
    `http://localhost/api/v1/document-preview-artifacts/${ids.artifact}/download-grants`,
    {
      body: JSON.stringify(body),
      headers: {
        Authorization: "Bearer user-header.user-payload.user-signature",
        "Content-Type": "application/json",
        "Idempotency-Key": "preview-download-route-001",
        "X-Correlation-Id": ids.correlation,
        "X-Request-Id": "request-preview-download-route-001",
        "X-Workspace-Id": ids.workspace,
      },
      method: "POST",
    },
  );
}

async function checksum(value: Uint8Array): Promise<string> {
  const copy = new Uint8Array(value.byteLength);
  copy.set(value);
  const digest = await crypto.subtle.digest("SHA-256", copy.buffer);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", publicKey);
  vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", serviceRole);
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("T-DOC-001 / T-STOR-001 document preview download grant route", () => {
  it("audits with the user session, resolves coordinates server-side, verifies, and signs", async () => {
    const bytes = new TextEncoder().encode(
      "<html>DRAFT / NON-PRODUCTION</html>",
    );
    const checksumSha256 = await checksum(bytes);
    const stored = new Uint8Array(bytes.byteLength);
    stored.set(bytes);
    const authorizationExpiresAt = new Date(Date.now() + 300_000).toISOString();
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
          {
            artifact_id: ids.artifact,
            audit_event_id: ids.audit,
            authorization_expires_at: authorizationExpiresAt,
            authorization_id: ids.authorization,
            byte_size: bytes.byteLength,
            checksum_sha256: checksumSha256,
            document_id: ids.document,
            filename: "preview.html",
            mime_type: "text/html; charset=utf-8",
            replayed: false,
          },
        ]),
      )
      .mockResolvedValueOnce(
        Response.json([
          {
            artifact_id: ids.artifact,
            authorization_expires_at: authorizationExpiresAt,
            authorization_id: ids.authorization,
            byte_size: bytes.byteLength,
            checksum_sha256: checksumSha256,
            document_id: ids.document,
            filename: "preview.html",
            mime_type: "text/html; charset=utf-8",
            signed_url_ttl_seconds: 60,
            storage_bucket: "document-previews",
            storage_object_path: `workspaces/${ids.workspace}/documents/${ids.document}/preview/${checksumSha256}.html`,
            workspace_id: ids.workspace,
          },
        ]),
      )
      .mockResolvedValueOnce(
        new Response(stored.buffer, {
          headers: { "Content-Type": "text/html; charset=utf-8" },
        }),
      )
      .mockResolvedValueOnce(
        Response.json({
          signedURL:
            "/storage/v1/object/sign/document-previews/exact?grant=fixture",
        }),
      );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createPreviewDownloadGrant(
      command({ expiresInSeconds: 60 }),
      { params: Promise.resolve({ id: ids.artifact }) },
    );

    expect(response.status).toBe(200);
    const responseBody = await response.json();
    expect(responseBody).toMatchObject({
      data: {
        artifactId: ids.artifact,
        auditEventId: ids.audit,
        documentId: ids.document,
        download: { url: expect.stringContaining("grant=fixture") },
      },
    });
    expect(JSON.stringify(responseBody)).not.toMatch(
      /authorizationId|storageBucket|storageObjectPath|service-role/iu,
    );

    const [userRpcUrl, userRpcInit] = fetchImplementation.mock.calls[0] ?? [];
    expect(userRpcUrl).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/authorize_document_preview_download",
    );
    expect(new Headers(userRpcInit?.headers).get("authorization")).toBe(
      "Bearer user-header.user-payload.user-signature",
    );
    const [serverRpcUrl, serverRpcInit] =
      fetchImplementation.mock.calls[1] ?? [];
    expect(serverRpcUrl).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/load_document_preview_download_authorization",
    );
    expect(new Headers(serverRpcInit?.headers).get("authorization")).toBe(
      `Bearer ${serviceRole}`,
    );
    expect(fetchImplementation.mock.calls[2]?.[1]?.method).toBe("GET");
    expect(fetchImplementation.mock.calls[3]?.[1]?.method).toBe("POST");
  });

  it("rejects an invalid expiry before database or storage traffic", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createPreviewDownloadGrant(
      command({ expiresInSeconds: 301 }),
      { params: Promise.resolve({ id: ids.artifact }) },
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toMatchObject({
      error: { code: "invalid_request_body" },
    });
    expect(fetchImplementation).not.toHaveBeenCalled();
  });
});
