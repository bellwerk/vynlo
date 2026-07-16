import { describe, expect, it, vi } from "vitest";

import { JobExecutionError } from "./job-runner";
import { SupabasePrivateArtifactStorage } from "./private-artifact-storage";
import { sha256Hex } from "./preview-renderer";

const body = new TextEncoder().encode("<html><body>preview</body></html>");
const write = {
  body,
  checksum: sha256Hex(body),
  contentType: "text/html; charset=utf-8",
  objectPath:
    "10000000-0000-4000-8000-000000000001/documents/10000000-0000-4000-8000-000000000002/preview/output.html",
  signal: new AbortController().signal,
} as const;

function storage(fetchImplementation: typeof fetch) {
  return new SupabasePrivateArtifactStorage({
    bucket: "preview-artifacts",
    fetchImplementation,
    serviceRoleKey: "x".repeat(32),
    supabaseUrl: "http://127.0.0.1:54321",
  });
}

describe("SupabasePrivateArtifactStorage", () => {
  it("uploads only through the authenticated private object endpoint", async () => {
    const fetchImplementation = vi.fn(
      async (
        _input: Parameters<typeof fetch>[0],
        _init?: Parameters<typeof fetch>[1],
      ) => {
        void _input;
        void _init;
        return Response.json({}, { status: 200 });
      },
    );

    await expect(storage(fetchImplementation).put(write)).resolves.toEqual({
      bucket: "preview-artifacts",
      byteSize: body.byteLength,
      checksum: write.checksum,
      objectPath: write.objectPath,
    });

    const [url, request] = fetchImplementation.mock.calls[0] ?? [];
    expect(url).toContain("/storage/v1/object/preview-artifacts/");
    expect(url).not.toContain("/public/");
    expect(request).toMatchObject({ method: "POST", signal: write.signal });
    expect(new Headers(request?.headers).get("x-upsert")).toBe("false");
    expect(new Headers(request?.headers).get("cache-control")).toBe(
      "private, no-store",
    );
  });

  it("treats identical deterministic-path content as a successful retry", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(null, { status: 400 }))
      .mockResolvedValueOnce(new Response(body, { status: 200 }));

    await expect(
      storage(fetchImplementation).put(write),
    ).resolves.toMatchObject({
      checksum: write.checksum,
    });
    expect(fetchImplementation).toHaveBeenCalledTimes(2);
    expect(fetchImplementation.mock.calls[1]?.[0]).toContain(
      "/storage/v1/object/authenticated/preview-artifacts/",
    );
  });

  it("fails closed when a deterministic path contains different bytes", async () => {
    const fetchImplementation = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(null, { status: 409 }))
      .mockResolvedValueOnce(new Response("different", { status: 200 }));

    const error = await storage(fetchImplementation)
      .put(write)
      .catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(JobExecutionError);
    expect(error).toMatchObject({
      classification: "permanent",
      code: "storage.deterministic_path_conflict",
    });
  });

  it("classifies rate limits without persisting provider response content", async () => {
    const fetchImplementation = vi.fn(
      async () =>
        new Response("sensitive provider body", {
          headers: { "Retry-After": "30" },
          status: 429,
        }),
    );

    const error = await storage(fetchImplementation)
      .put(write)
      .catch((caught: unknown) => caught);
    expect(error).toMatchObject({
      classification: "transient",
      retryAfterSeconds: 30,
    });
    expect(JSON.stringify(error)).not.toContain("provider body");
  });

  it("rejects a checksum mismatch before any storage request", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    await expect(
      storage(fetchImplementation).put({ ...write, checksum: "a".repeat(64) }),
    ).rejects.toMatchObject({ classification: "validation" });
    expect(fetchImplementation).not.toHaveBeenCalled();
  });
});
