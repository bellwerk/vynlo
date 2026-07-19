import { beforeEach, describe, expect, it, vi } from "vitest";

import { PostgrestCommandError } from "./postgrest-error";
import { SupabaseDocumentPreviewDownloadGrantPort } from "./document-preview-download-grant.server";

const now = Date.parse("2026-07-16T20:00:00.000Z");
const ids = Object.freeze({
  artifact: "10000000-0000-4000-8000-000000000001",
  authorization: "10000000-0000-4000-8000-000000000002",
  document: "10000000-0000-4000-8000-000000000003",
  workspace: "10000000-0000-4000-8000-000000000004",
});
const bytes = new TextEncoder().encode("<html>DRAFT / NON-PRODUCTION</html>");

async function sha256(value: Uint8Array): Promise<string> {
  const copy = new Uint8Array(value.byteLength);
  copy.set(value);
  const digest = await crypto.subtle.digest("SHA-256", copy.buffer);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function input(checksumSha256: string) {
  return {
    artifactId: ids.artifact,
    authorizationExpiresAt: "2026-07-16T20:05:00.000Z",
    authorizationId: ids.authorization,
    byteSize: bytes.byteLength,
    checksumSha256,
    documentId: ids.document,
    expiresInSeconds: 60,
    filename: "preview.html" as const,
    mimeType: "text/html; charset=utf-8" as const,
    workspaceId: ids.workspace,
  };
}

function row(checksumSha256: string) {
  return {
    artifact_id: ids.artifact,
    authorization_expires_at: "2026-07-16T20:05:00.000Z",
    authorization_id: ids.authorization,
    byte_size: bytes.byteLength,
    checksum_sha256: checksumSha256,
    document_id: ids.document,
    filename: "preview.html",
    mime_type: "text/html; charset=utf-8",
    signed_url_ttl_seconds: 60,
    storage_bucket: "preview-artifacts",
    storage_object_path: `workspaces/${ids.workspace}/documents/${ids.document}/preview/${checksumSha256}.html`,
    workspace_id: ids.workspace,
  };
}

function responseBytes(
  value: Uint8Array,
  contentType = "text/html; charset=utf-8",
) {
  const copy = new Uint8Array(value.byteLength);
  copy.set(value);
  return new Response(copy.buffer, {
    headers: {
      "content-length": String(value.byteLength),
      "content-type": contentType,
    },
    status: 200,
  });
}

describe("T-DOC-001 / T-STOR-001 SupabaseDocumentPreviewDownloadGrantPort", () => {
  let checksumSha256: string;

  beforeEach(async () => {
    checksumSha256 = await sha256(bytes);
  });

  it("loads service-only coordinates, verifies exact bytes, and signs briefly", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json([row(checksumSha256)]))
      .mockResolvedValueOnce(responseBytes(bytes))
      .mockResolvedValueOnce(
        Response.json({
          signedURL:
            "/storage/v1/object/sign/preview-artifacts/workspaces/signed?token=opaque",
        }),
      );
    const port = new SupabaseDocumentPreviewDownloadGrantPort({
      fetchImplementation,
      now: () => now,
      serviceRoleKey: "service-role-key-with-enough-length",
      supabaseUrl: "https://example.supabase.co",
    });

    await expect(port.issue(input(checksumSha256))).resolves.toEqual({
      expiresAt: "2026-07-16T20:01:00.000Z",
      url: "https://example.supabase.co/storage/v1/object/sign/preview-artifacts/workspaces/signed?token=opaque",
    });
    expect(fetchImplementation).toHaveBeenNthCalledWith(
      1,
      "https://example.supabase.co/rest/v1/rpc/load_document_preview_download_authorization",
      expect.objectContaining({
        body: JSON.stringify({ p_authorization_id: ids.authorization }),
        method: "POST",
      }),
    );
    expect(fetchImplementation).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining("/storage/v1/object/sign/preview-artifacts/"),
      expect.objectContaining({ body: JSON.stringify({ expiresIn: 60 }) }),
    );
  });

  it("never trusts provider coordinates returned by the user-facing authorization RPC", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
          { ...row(checksumSha256), artifact_id: crypto.randomUUID() },
        ]),
      );
    const port = new SupabaseDocumentPreviewDownloadGrantPort({
      fetchImplementation,
      now: () => now,
      serviceRoleKey: "service-role-key-with-enough-length",
      supabaseUrl: "https://example.supabase.co",
    });

    await expect(port.issue(input(checksumSha256))).rejects.toMatchObject({
      code: "conflict",
      status: 409,
    });
    expect(fetchImplementation).toHaveBeenCalledTimes(1);
  });

  it("fails closed when stored bytes drift from immutable provenance", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json([row(checksumSha256)]))
      .mockResolvedValueOnce(
        responseBytes(new TextEncoder().encode("<html>tampered</html>")),
      );
    const port = new SupabaseDocumentPreviewDownloadGrantPort({
      fetchImplementation,
      now: () => now,
      serviceRoleKey: "service-role-key-with-enough-length",
      supabaseUrl: "https://example.supabase.co",
    });

    await expect(port.issue(input(checksumSha256))).rejects.toMatchObject({
      code: "conflict",
      status: 409,
    });
    expect(fetchImplementation).toHaveBeenCalledTimes(2);
  });

  it("does not sign after the audited authorization expires", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json([row(checksumSha256)]));
    const port = new SupabaseDocumentPreviewDownloadGrantPort({
      fetchImplementation,
      now: () => Date.parse("2026-07-16T20:05:00.000Z"),
      serviceRoleKey: "service-role-key-with-enough-length",
      supabaseUrl: "https://example.supabase.co",
    });

    await expect(port.issue(input(checksumSha256))).rejects.toMatchObject({
      code: "conflict",
      status: 409,
    });
    expect(fetchImplementation).toHaveBeenCalledTimes(1);
  });

  it("rejects a signed URL on a different origin", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json([row(checksumSha256)]))
      .mockResolvedValueOnce(responseBytes(bytes))
      .mockResolvedValueOnce(
        Response.json({ signedURL: "https://attacker.invalid/preview" }),
      );
    const port = new SupabaseDocumentPreviewDownloadGrantPort({
      fetchImplementation,
      now: () => now,
      serviceRoleKey: "service-role-key-with-enough-length",
      supabaseUrl: "https://example.supabase.co",
    });

    await expect(port.issue(input(checksumSha256))).rejects.toBeInstanceOf(
      PostgrestCommandError,
    );
  });

  it("rejects unsafe service configuration before any request", () => {
    expect(
      () =>
        new SupabaseDocumentPreviewDownloadGrantPort({
          serviceRoleKey: "short",
          supabaseUrl: "https://example.supabase.co/path",
        }),
    ).toThrow(PostgrestCommandError);
  });
});
