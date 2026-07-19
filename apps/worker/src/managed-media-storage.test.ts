import { describe, expect, it, vi } from "vitest";
import {
  materializeMediaSource,
  mediaSha256Hex,
  SupabaseManagedMediaStorage,
} from "./managed-media-storage";

const serviceRoleKey = "service-role-key-that-is-server-only";
const object = {
  bucket: "media-private",
  objectKey:
    "workspaces/10000000-0000-4000-8000-000000000001/uploads/a9000000-0000-4000-8000-000000000001/source",
} as const;

describe("T-MED-004 / T-STOR-001 SupabaseManagedMediaStorage", () => {
  it("issues a private exact-key upload grant without browser credentials", async () => {
    const request = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json({
        url: "/storage/v1/object/upload/sign/media-private/exact?grant=fixture",
      }),
    );
    const storage = new SupabaseManagedMediaStorage({
      fetchImplementation: request,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    const grant = await storage.createUploadGrant({
      expectedByteSize: 100,
      expectedChecksumSha256: "a".repeat(64),
      expectedMimeType: "image/jpeg",
      expiresInSeconds: 300,
      object,
    });

    expect(grant.objectKey).toBe(object.objectKey);
    expect(grant.requiredHeaders).toEqual({
      "Content-Type": "image/jpeg",
      "x-upsert": "false",
    });
    expect(grant.url).toContain("/storage/v1/object/upload/sign/");
    const init = request.mock.calls[0]?.[1];
    expect(init?.method).toBe("POST");
    expect(init?.body).toBe("{}");
    expect(JSON.stringify(grant)).not.toContain(serviceRoleKey);
  });

  it("writes checksum-verified immutable bytes", async () => {
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const checksum = await mediaSha256Hex(bytes);
    const request = vi
      .fn<typeof fetch>()
      .mockResolvedValue(new Response("{}", { status: 200 }));
    const storage = new SupabaseManagedMediaStorage({
      fetchImplementation: request,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    await expect(
      storage.putIfAbsent({
        body: bytes,
        byteSize: bytes.byteLength,
        checksumSha256: checksum,
        mimeType: "image/webp",
        object,
      }),
    ).resolves.toEqual({
      ...object,
      byteSize: 4,
      checksumSha256: checksum,
      mimeType: "image/webp",
    });
    expect(
      new Headers(request.mock.calls[0]?.[1]?.headers).get("x-upsert"),
    ).toBe("false");
  });

  it("rejects a deterministic-path conflict when provider MIME differs", async () => {
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const checksum = await mediaSha256Hex(bytes);
    const request = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(new Response("conflict", { status: 409 }))
      .mockResolvedValueOnce(
        new Response(bytes, {
          headers: {
            "Content-Type": "image/png",
          },
          status: 200,
        }),
      );
    const storage = new SupabaseManagedMediaStorage({
      fetchImplementation: request,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    await expect(
      storage.putIfAbsent({
        body: bytes,
        byteSize: bytes.byteLength,
        checksumSha256: checksum,
        mimeType: "image/webp",
        object,
      }),
    ).rejects.toMatchObject({
      code: "media.storage_deterministic_path_conflict",
    });
    expect(request).toHaveBeenCalledTimes(2);
  });

  it("fails closed instead of a racy GET-then-DELETE when bytes can be replaced", async () => {
    const request = vi.fn<typeof fetch>().mockImplementation(() => {
      throw new Error(
        "A provider request would allow replacement between check and delete.",
      );
    });
    const storage = new SupabaseManagedMediaStorage({
      fetchImplementation: request,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    await expect(
      storage.delete({ ifChecksumSha256: "a".repeat(64), object }),
    ).rejects.toMatchObject({
      classification: "permanent",
      code: "media.storage_atomic_delete_unsupported",
    });
    expect(request).not.toHaveBeenCalled();
  });

  it("streams provider reads and cancels before buffering beyond the caller cap", async () => {
    const cancelled = vi.fn();
    let pullCount = 0;
    const request = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(
        new ReadableStream<Uint8Array>({
          cancel: cancelled,
          pull(controller) {
            pullCount += 1;
            controller.enqueue(new Uint8Array([1, 2, 3, 4]));
          },
        }),
        { headers: { "Content-Type": "image/jpeg" } },
      ),
    );
    const storage = new SupabaseManagedMediaStorage({
      fetchImplementation: request,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    const source = await storage.read({ object });
    await expect(materializeMediaSource(source, 5)).rejects.toMatchObject({
      code: "media.storage_invalid_body",
    });
    expect(pullCount).toBeLessThanOrEqual(3);
    expect(cancelled).toHaveBeenCalled();
  });

  it("verifies immutable provider provenance before issuing a download grant", async () => {
    const bytes = new Uint8Array([4, 3, 2, 1]);
    const checksum = await mediaSha256Hex(bytes);
    const request = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        new Response(bytes, {
          headers: {
            "Content-Type": "image/webp",
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
    const storage = new SupabaseManagedMediaStorage({
      fetchImplementation: request,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    await expect(
      storage.createDownloadGrant({
        expectedByteSize: bytes.byteLength,
        expectedChecksumSha256: checksum,
        expectedGeneration: '"generation-1"',
        expectedMimeType: "image/webp",
        expiresInSeconds: 60,
        object,
      }),
    ).resolves.toMatchObject({ ...object });
    expect(request).toHaveBeenCalledTimes(2);
    expect(request.mock.calls[0]?.[1]?.method).toBe("GET");
    expect(request.mock.calls[1]?.[1]?.method).toBe("POST");
  });

  it("refuses to sign a drifted object", async () => {
    const bytes = new Uint8Array([9, 8, 7, 6]);
    const request = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(bytes, {
        headers: { "Content-Type": "image/webp", ETag: '"generation-2"' },
      }),
    );
    const storage = new SupabaseManagedMediaStorage({
      fetchImplementation: request,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });

    await expect(
      storage.createDownloadGrant({
        expectedByteSize: bytes.byteLength,
        expectedChecksumSha256: "a".repeat(64),
        expectedGeneration: '"generation-1"',
        expectedMimeType: "image/webp",
        expiresInSeconds: 60,
        object,
      }),
    ).rejects.toMatchObject({ code: "media.storage_provider_drift" });
    expect(request).toHaveBeenCalledOnce();
  });

  it("streams a legal original with provider generation and normalized MIME provenance", async () => {
    const bytes = new TextEncoder().encode("%PDF-1.7\nfixture");
    const request = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(bytes, {
        headers: {
          "Content-Length": String(bytes.byteLength),
          "Content-Type": "application/pdf; charset=binary",
          ETag: '"legal-generation-1"',
        },
      }),
    );
    const storage = new SupabaseManagedMediaStorage({
      fetchImplementation: request,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });
    const legal = await storage.readLegalOriginal({ object });
    expect(legal).toMatchObject({
      generation: '"legal-generation-1"',
      providerMimeType: "application/pdf",
    });
    await expect(
      materializeMediaSource(legal.source, 50_000_000),
    ).resolves.toEqual(bytes);
    expect(request.mock.calls[0]?.[1]?.method).toBe("GET");
  });

  it("refuses a legal original without immutable provider generation", async () => {
    const request = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(new TextEncoder().encode("%PDF-1.7\nfixture"), {
        headers: { "Content-Type": "application/pdf" },
      }),
    );
    const storage = new SupabaseManagedMediaStorage({
      fetchImplementation: request,
      serviceRoleKey,
      supabaseUrl: "https://storage.example.invalid",
    });
    await expect(storage.readLegalOriginal({ object })).rejects.toMatchObject({
      code: "media.storage_invalid_object_provenance",
    });
  });
});
