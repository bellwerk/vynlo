import { describe, expect, it, vi } from "vitest";

import { SupabaseVerifiedMediaDownloadGrantPort } from "./media-download-grant.server";

const serviceRoleKey = "server-only-service-role-material";
const now = Date.parse("2026-07-16T20:00:00.000Z");
const ids = Object.freeze({
  authorization: "10000000-0000-4000-8000-000000000001",
  file: "10000000-0000-4000-8000-000000000002",
  workspace: "10000000-0000-4000-8000-000000000003",
});

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new Uint8Array(bytes).buffer,
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function input(checksumSha256: string) {
  return {
    authorizationExpiresAt: "2026-07-16T20:05:00.000Z",
    authorizationId: ids.authorization,
    byteSize: 4,
    checksumSha256,
    expiresInSeconds: 60,
    mediaFileId: ids.file,
    mediaKind: "legal_document" as const,
    mimeType: "application/pdf",
    workspaceId: ids.workspace,
  };
}

function row(checksumSha256: string) {
  return {
    authorization_expires_at: "2026-07-16T20:05:00.000Z",
    authorization_id: ids.authorization,
    byte_size: 4,
    checksum_sha256: checksumSha256,
    media_file_id: ids.file,
    media_kind: "legal_document",
    mime_type: "application/pdf",
    signed_url_ttl_seconds: 60,
    storage_bucket: "media-private",
    storage_generation: '"generation-1"',
    storage_object_key: `workspaces/${ids.workspace}/documents/original.pdf`,
    workspace_id: ids.workspace,
  };
}

describe("T-STOR-001 server-only verified media download grants", () => {
  it("hashes exact provider bytes and generation before signing", async () => {
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const checksum = await sha256Hex(bytes);
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json([row(checksum)]))
      .mockResolvedValueOnce(
        new Response(bytes, {
          headers: {
            "Content-Type": "application/pdf",
            ETag: '"generation-1"',
          },
        }),
      )
      .mockResolvedValueOnce(
        Response.json({
          signedURL:
            "/storage/v1/object/sign/media-private/exact?grant=fixture",
        }),
      );
    const port = new SupabaseVerifiedMediaDownloadGrantPort({
      fetchImplementation,
      now: () => now,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    await expect(port.issue(input(checksum))).resolves.toMatchObject({
      url: expect.stringContaining(
        "storage.example.invalid/storage/v1/object/sign",
      ),
    });
    expect(fetchImplementation).toHaveBeenCalledTimes(3);
    expect(fetchImplementation).toHaveBeenNthCalledWith(
      1,
      "https://storage.example.invalid/rest/v1/rpc/load_managed_media_download_authorization",
      expect.objectContaining({
        body: JSON.stringify({ p_authorization_id: ids.authorization }),
        method: "POST",
      }),
    );
    expect(
      new Headers(fetchImplementation.mock.calls[0]?.[1]?.headers).get(
        "authorization",
      ),
    ).toBe(`Bearer ${serviceRoleKey}`);
    expect(fetchImplementation.mock.calls[1]?.[1]?.method).toBe("GET");
    expect(fetchImplementation.mock.calls[2]?.[1]?.method).toBe("POST");
  });

  it("fails closed on provider drift without requesting a signed URL", async () => {
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const checksum = await sha256Hex(bytes);
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json([row(checksum)]))
      .mockResolvedValueOnce(
        new Response(bytes, {
          headers: {
            "Content-Type": "application/pdf",
            ETag: '"generation-2"',
          },
        }),
      );
    const port = new SupabaseVerifiedMediaDownloadGrantPort({
      fetchImplementation,
      now: () => now,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    await expect(port.issue(input(checksum))).rejects.toMatchObject({
      code: "conflict",
      status: 409,
    });
    expect(fetchImplementation).toHaveBeenCalledTimes(2);
  });

  it("rejects a loader row for a different file before reading provider bytes", async () => {
    const checksum = "a".repeat(64);
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
          { ...row(checksum), media_file_id: crypto.randomUUID() },
        ]),
      );
    const port = new SupabaseVerifiedMediaDownloadGrantPort({
      fetchImplementation,
      now: () => now,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    await expect(port.issue(input(checksum))).rejects.toMatchObject({
      code: "conflict",
      status: 409,
    });
    expect(fetchImplementation).toHaveBeenCalledOnce();
  });

  it("rejects a loader row for a different workspace before reading provider bytes", async () => {
    const checksum = "a".repeat(64);
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json([
          { ...row(checksum), workspace_id: crypto.randomUUID() },
        ]),
      );
    const port = new SupabaseVerifiedMediaDownloadGrantPort({
      fetchImplementation,
      now: () => now,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    await expect(port.issue(input(checksum))).rejects.toMatchObject({
      code: "conflict",
      status: 409,
    });
    expect(fetchImplementation).toHaveBeenCalledOnce();
  });
});
