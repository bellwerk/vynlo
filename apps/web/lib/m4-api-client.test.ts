import { afterEach, describe, expect, it, vi } from "vitest";

import {
  m4DocumentActionEligibility,
  parseM4JsonArray,
  parseM4JsonObject,
  requestM4Json,
} from "./m4-api-client";

const context = {
  accessToken: "header.payload.signature",
  workspaceId: "40000000-0000-4000-8000-000000000001",
};

describe("T-API-001 / M4-CFG-AC-002 browser command boundary", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("keeps workspace authority in verified headers and sends idempotency", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json({ data: { document_id: "document" } }, { status: 202 }),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    await requestM4Json({
      body: { dealId: "deal", reason: "Approved operation" },
      context,
      idempotencyKey: "m4-official-synthetic-0001",
      method: "POST",
      path: "/api/v1/documents/official",
    });

    const [, init] = fetchImplementation.mock.calls[0] ?? [];
    const headers = new Headers(init?.headers);
    expect(headers.get("x-workspace-id")).toBe(context.workspaceId);
    expect(headers.get("idempotency-key")).toBe("m4-official-synthetic-0001");
    expect(JSON.parse(String(init?.body))).not.toHaveProperty("workspaceId");
  });

  it("accepts only the JSON container shape expected by safe forms", () => {
    expect(parseM4JsonObject('{"passed":true}')).toEqual({ passed: true });
    expect(parseM4JsonArray("[1,2]")).toEqual([1, 2]);
    expect(() => parseM4JsonObject("[]")).toThrow("json_object_required");
    expect(() => parseM4JsonArray("{}")).toThrow("json_array_required");
  });
});

describe("M4-DOC-AC-006..009 document action eligibility", () => {
  const signedScan = {
    byte_size: 512,
    checksum_sha256: "a".repeat(64),
    created_at: "2026-07-16T12:00:00Z",
    current: true,
    filename: "signed.pdf",
    id: "40000000-0000-4000-8000-000000000011",
    mime_type: "application/pdf",
    role: "signed_scan" as const,
    version: 1,
  };
  const reviewedDeadLetter = {
    attempt_count: 3,
    failure_code: "renderer.failed",
    job_id: "40000000-0000-4000-8000-000000000012",
    review_required: true,
    status: "dead_letter" as const,
    updated_at: "2026-07-16T12:00:00Z",
  };

  it("requires the reviewed latest dead letter before offering retry", () => {
    expect(
      m4DocumentActionEligibility({
        files: [],
        jobs: [reviewedDeadLetter],
        mode: "official",
        status: "generation_failed",
      }),
    ).toMatchObject({
      markSigned: false,
      retryRender: true,
      supersede: false,
      void: true,
    });
    expect(
      m4DocumentActionEligibility({
        files: [],
        jobs: [{ ...reviewedDeadLetter, review_required: false }],
        mode: "official",
        status: "generation_failed",
      }).retryRender,
    ).toBe(false);
  });

  it("offers signing only for a generated official with a current signed scan", () => {
    expect(
      m4DocumentActionEligibility({
        files: [signedScan],
        jobs: [],
        mode: "official",
        status: "generated",
      }),
    ).toMatchObject({ markSigned: true, supersede: true, void: true });
    expect(
      m4DocumentActionEligibility({
        files: [{ ...signedScan, current: false }],
        jobs: [],
        mode: "official",
        status: "generated",
      }).markSigned,
    ).toBe(false);
  });

  it.each(["generated", "signed_received", "completed"] as const)(
    "offers final mutations for eligible official status %s",
    (status) => {
      expect(
        m4DocumentActionEligibility({
          files: [],
          jobs: [],
          mode: "official",
          status,
        }),
      ).toMatchObject({ supersede: true, void: true });
    },
  );

  it("never offers official lifecycle actions for previews or terminal officials", () => {
    expect(
      m4DocumentActionEligibility({
        files: [signedScan],
        jobs: [reviewedDeadLetter],
        mode: "preview",
        status: "generated",
      }),
    ).toEqual({
      markSigned: false,
      retryRender: false,
      supersede: false,
      void: false,
    });
    expect(
      m4DocumentActionEligibility({
        files: [],
        jobs: [],
        mode: "official",
        status: "superseded",
      }),
    ).toEqual({
      markSigned: false,
      retryRender: false,
      supersede: false,
      void: false,
    });
    expect(
      m4DocumentActionEligibility({
        files: [],
        jobs: [],
        mode: "official",
        status: "voided",
      }),
    ).toEqual({
      markSigned: false,
      retryRender: false,
      supersede: false,
      void: false,
    });
  });
});
