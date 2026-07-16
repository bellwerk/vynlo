import { describe, expect, it, vi } from "vitest";
import { JobStoreError, PostgrestJobStore } from "./job-store";

describe("PostgrestJobStore", () => {
  it("claims jobs through the service-only RPC and maps the lease contract", async () => {
    const fetchImplementation = vi.fn(
      async (
        _input: Parameters<typeof fetch>[0],
        _init?: Parameters<typeof fetch>[1],
      ) => {
        void _input;
        void _init;
        return Response.json([
          {
            attempt_number: 1,
            causation_id: null,
            correlation_id: "00000000-0000-4000-8000-000000000010",
            entity_id: "00000000-0000-4000-8000-000000000020",
            entity_type: "document_preview",
            idempotency_key: "preview-job-request-1",
            job_id: "00000000-0000-4000-8000-000000000030",
            job_type: "documents.render_preview",
            lease_expires_at: "2026-07-16T12:01:00.000Z",
            lease_token: "00000000-0000-4000-8000-000000000040",
            max_attempts: 8,
            outbox_event_id: "00000000-0000-4000-8000-000000000050",
            payload: { previewRequestId: "preview-1" },
            payload_schema_version: 1,
            workspace_id: "00000000-0000-4000-8000-000000000060",
          },
        ]);
      },
    );
    const store = new PostgrestJobStore({
      fetchImplementation,
      serviceRoleKey: "x".repeat(32),
      supabaseUrl: "http://127.0.0.1:54321",
    });

    const jobs = await store.claimJobs({
      jobTypes: ["documents.render_preview"],
      leaseSeconds: 60,
      limit: 5,
      workerId: "worker-a",
    });

    expect(jobs).toHaveLength(1);
    expect(jobs[0]).toMatchObject({
      attemptNumber: 1,
      idempotencyKey: "preview-job-request-1",
      jobType: "documents.render_preview",
      payloadSchemaVersion: 1,
    });
    const [url, request] = fetchImplementation.mock.calls[0] ?? [];
    expect(url).toBe("http://127.0.0.1:54321/rest/v1/rpc/claim_jobs");
    expect(request).toMatchObject({ method: "POST" });
    expect(new Headers(request?.headers).get("content-profile")).toBe("app");
    expect(JSON.parse(String(request?.body))).toEqual({
      p_job_types: ["documents.render_preview"],
      p_lease_seconds: 60,
      p_limit: 5,
      p_worker_id: "worker-a",
    });
  });

  it("fails closed without echoing database response details", async () => {
    const store = new PostgrestJobStore({
      fetchImplementation: vi.fn(
        async () => new Response("internal database detail", { status: 500 }),
      ),
      serviceRoleKey: "x".repeat(32),
      supabaseUrl: "https://example.invalid",
    });

    const error = await store
      .claimJobs({ leaseSeconds: 60, limit: 1, workerId: "worker-a" })
      .catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(JobStoreError);
    expect((error as Error).message).not.toContain("database detail");
  });

  it("reclaims expired leases through the bounded service-only RPC", async () => {
    const fetchImplementation = vi.fn(
      async (
        _input: Parameters<typeof fetch>[0],
        _init?: Parameters<typeof fetch>[1],
      ) => {
        void _input;
        void _init;
        return Response.json([
          {
            job_id: "00000000-0000-4000-8000-000000000030",
            resulting_status: "retry_wait",
            retry_at: "2026-07-16T12:02:00.000Z",
          },
        ]);
      },
    );
    const store = new PostgrestJobStore({
      fetchImplementation,
      serviceRoleKey: "x".repeat(32),
      supabaseUrl: "http://127.0.0.1:54321",
    });

    await expect(store.reclaimExpiredJobs(25)).resolves.toBe(1);
    const [url, request] = fetchImplementation.mock.calls[0] ?? [];
    expect(url).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/reclaim_expired_job_leases",
    );
    expect(JSON.parse(String(request?.body))).toEqual({ p_limit: 25 });
    expect(new Headers(request?.headers).get("content-profile")).toBe("app");
  });

  it("rejects plaintext remote transports", () => {
    expect(
      () =>
        new PostgrestJobStore({
          serviceRoleKey: "x".repeat(32),
          supabaseUrl: "http://example.invalid",
        }),
    ).toThrow(/HTTPS/u);
  });
});
