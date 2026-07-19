// Stable test IDs: T-DOC-004, T-DOC-005, T-JOB-003.
import { describe, expect, it, vi } from "vitest";

import { PostgrestOfficialDocumentRepository } from "./official-document-repository";

const id = (suffix: string) =>
  `10000000-0000-4000-8000-${suffix.padStart(12, "0")}`;

describe("M4 official document worker repository", () => {
  it("loads only through the lease-fenced app RPC", async () => {
    const fetchImplementation = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json([
        {
          asset_manifest: {},
          completed_aggregate_version: null,
          completed_byte_size: null,
          completed_checksum: null,
          completed_file_id: null,
          document_id: id("1"),
          font_manifest: {},
          locale: "en-CA",
          official_number: "DOC-0001",
          render_input_checksum: "a".repeat(64),
          render_input_snapshot: { document: { fields: {} } },
          renderer_version: "playwright-pdf-v1",
          source_bundle_checksum: "b".repeat(64),
          source_css: "",
          source_html: "<p>Official</p>",
          version_snapshot: { templateVersionId: id("2") },
          version_snapshot_checksum: "c".repeat(64),
        },
      ]),
    );
    const repository = new PostgrestOfficialDocumentRepository({
      fetchImplementation,
      serviceRoleKey: "x".repeat(32),
      supabaseUrl: "http://127.0.0.1:54321",
    });
    await expect(
      repository.load({
        documentId: id("1"),
        jobId: id("3"),
        leaseToken: id("4"),
        signal: new AbortController().signal,
        workerId: "worker-m4-1",
        workspaceId: id("5"),
      }),
    ).resolves.toMatchObject({
      documentId: id("1"),
      officialNumber: "DOC-0001",
      rendererVersion: "playwright-pdf-v1",
      completion: null,
    });
    expect(String(fetchImplementation.mock.calls[0]?.[0])).toContain(
      "/rest/v1/rpc/m4_load_official_document_render",
    );
    expect(fetchImplementation.mock.calls[0]?.[1]).toMatchObject({
      headers: expect.objectContaining({ "Content-Profile": "app" }),
      method: "POST",
    });
  });

  it("lease-verifies failure without predicting or settling the durable job", async () => {
    const fetchImplementation = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json([
        {
          document_status: "generating",
          job_status: "running",
          retry_at: null,
          review_required: false,
        },
      ]),
    );
    const repository = new PostgrestOfficialDocumentRepository({
      fetchImplementation,
      serviceRoleKey: "x".repeat(32),
      supabaseUrl: "http://127.0.0.1:54321",
    });
    await repository.recordFailure({
      classification: "transient",
      correlationId: id("6"),
      documentId: id("1"),
      errorCode: "document.pdf_render_timeout",
      errorDetailSafe: "The bounded official PDF render timed out.",
      jobId: id("3"),
      leaseToken: id("4"),
      requestId: `job:${id("3")}:failure`,
      signal: new AbortController().signal,
      workerId: "worker-m4-1",
      workspaceId: id("5"),
    });
    const body = JSON.parse(
      String((fetchImplementation.mock.calls[0]?.[1] as RequestInit).body),
    ) as Record<string, unknown>;
    expect(body).not.toHaveProperty("p_job_status");
    expect(body).toMatchObject({
      p_error_classification: "transient",
      p_job_id: id("3"),
    });
  });
});
