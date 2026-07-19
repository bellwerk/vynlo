// Stable test IDs: T-DOC-004, T-EXP-002, T-JOB-003, T-STOR-001.
import { describe, expect, it, vi } from "vitest";

import { SupabaseImmutableArtifactStorage } from "./immutable-artifact-storage";

const bytes = new TextEncoder().encode("immutable artifact");
const checksum =
  "eca6f2c7063ef1bf0c7a3ee5beab0e50fb58b13e205106677b8a2470ad8e00ab";

function storage(fetchImplementation: typeof fetch) {
  return new SupabaseImmutableArtifactStorage({
    allowedContentTypes: ["application/pdf"],
    bucket: "documents-private",
    fetchImplementation,
    maximumBytes: 1_000_000,
    serviceRoleKey: "x".repeat(32),
    supabaseUrl: "http://127.0.0.1:54321",
  });
}

describe("M4 immutable artifact storage", () => {
  it("creates an exact private key and returns verified generation provenance", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(new Response("{}", { status: 200 }))
      .mockResolvedValueOnce(
        new Response(bytes, {
          headers: { "content-type": "application/pdf", etag: '"g-1"' },
          status: 200,
        }),
      );
    await expect(
      storage(fetchImplementation).put({
        body: bytes,
        checksum,
        contentType: "application/pdf",
        objectPath: "workspace/documents/document/generated/v1/file.pdf",
        signal: new AbortController().signal,
      }),
    ).resolves.toEqual({
      bucket: "documents-private",
      byteSize: bytes.byteLength,
      checksum,
      contentType: "application/pdf",
      generation: '"g-1"',
      objectPath: "workspace/documents/document/generated/v1/file.pdf",
    });
    const upload = new URL(String(fetchImplementation.mock.calls[0]?.[0]));
    expect(upload.pathname).toContain("/storage/v1/object/documents-private/");
    expect(fetchImplementation.mock.calls[0]?.[1]).toMatchObject({
      headers: expect.objectContaining({ "x-upsert": "false" }),
      method: "POST",
    });
  });

  it("verifies a create-only replay and rejects provider drift", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(new Response("conflict", { status: 409 }))
      .mockResolvedValueOnce(
        new Response("different", {
          headers: { "content-type": "application/pdf", etag: '"g-2"' },
          status: 200,
        }),
      );
    await expect(
      storage(fetchImplementation).put({
        body: bytes,
        checksum,
        contentType: "application/pdf",
        objectPath: "workspace/documents/document/generated/v1/file.pdf",
        signal: new AbortController().signal,
      }),
    ).rejects.toMatchObject({
      code: "artifact.storage_deterministic_path_conflict",
    });
  });

  it("rejects unsupported content before storage is addressed", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    await expect(
      storage(fetchImplementation).put({
        body: bytes,
        checksum,
        contentType: "text/html; charset=utf-8",
        objectPath: "workspace/document.html",
        signal: new AbortController().signal,
      }),
    ).rejects.toMatchObject({ code: "artifact.storage_receipt_mismatch" });
    expect(fetchImplementation).not.toHaveBeenCalled();
  });
});
