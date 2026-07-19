// M4-DOC-AC-010, M4-EXP-AC-004, T-DOC-006, T-EXP-002.
import { createHash } from "node:crypto";

import { describe, expect, it, vi } from "vitest";

import { SupabaseM4DownloadGrantPort } from "./m4-download-grant.server";

const now = Date.parse("2026-07-16T12:00:00.000Z");
const workspaceId = "00000000-0000-4000-8000-000000000001";
const authorizationId = "00000000-0000-4000-8000-000000000002";
const ownerId = "00000000-0000-4000-8000-000000000003";
const fileId = "00000000-0000-4000-8000-000000000004";
const bytes = new TextEncoder().encode("verified M4 fixture");
const checksumSha256 = createHash("sha256").update(bytes).digest("hex");

describe("M4 verified download grants", () => {
  it.each([
    [
      "document" as const,
      "m4_load_document_file_download_authorization",
      { document_file_id: fileId, document_id: ownerId },
    ],
    [
      "export" as const,
      "m4_load_export_download_authorization",
      { export_file_id: fileId, export_run_id: ownerId },
    ],
  ])(
    "uses the exact %s service-only loader and verifies immutable bytes",
    async (kind, loader, identity) => {
      const fetchImplementation = vi
        .fn<typeof fetch>()
        .mockResolvedValueOnce(
          Response.json([
            {
              authorization_expires_at: "2026-07-16T12:01:00.000Z",
              authorization_id: authorizationId,
              byte_size: bytes.byteLength,
              checksum_sha256: checksumSha256,
              filename: "fixture.pdf",
              ...identity,
              mime_type: "application/pdf",
              signed_url_ttl_seconds: 60,
              storage_bucket: "m4-private",
              storage_generation: '"generation-1"',
              storage_object_path: `${workspaceId}/fixture.pdf`,
              verification_receipt: { verified: true },
              workspace_id: workspaceId,
            },
          ]),
        )
        .mockResolvedValueOnce(
          new Response(bytes, {
            headers: {
              "content-length": String(bytes.byteLength),
              "content-type": "application/pdf",
              etag: '"generation-1"',
            },
          }),
        )
        .mockResolvedValueOnce(
          Response.json({
            signedURL:
              "/storage/v1/object/sign/m4-private/signed?token=opaque-fixture",
          }),
        );
      const port = new SupabaseM4DownloadGrantPort({
        fetchImplementation,
        now: () => now,
        serviceRoleKey: "service-role-fixture-key-long-enough",
        supabaseUrl: "https://example.supabase.co",
      });

      await expect(
        port.issue({
          authorizationExpiresAt: "2026-07-16T12:01:00.000Z",
          authorizationId,
          byteSize: bytes.byteLength,
          checksumSha256,
          fileId,
          filename: "fixture.pdf",
          kind,
          mimeType: "application/pdf",
          ownerId,
          workspaceId,
        }),
      ).resolves.toEqual({
        expiresAt: "2026-07-16T12:01:00.000Z",
        url: "https://example.supabase.co/storage/v1/object/sign/m4-private/signed?token=opaque-fixture",
      });

      expect(fetchImplementation.mock.calls[0]?.[0]).toBe(
        `https://example.supabase.co/rest/v1/rpc/${loader}`,
      );
      expect(
        JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
      ).toEqual({
        p_authorization_id: authorizationId,
      });
    },
  );
});
