import { afterEach, describe, expect, it, vi } from "vitest";

import { M3ApiError, requestM3Json } from "./m3-api-client";

const context = {
  accessToken: "header.payload.signature",
  workspaceId: "10000000-0000-4000-8000-000000000001",
};

describe("T-API-001 Milestone 3 browser command boundary", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("derives workspace authority from headers and keeps it out of the body", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json({ data: { leadId: "lead" } }, { status: 201 }),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    await expect(
      requestM3Json<{ leadId: string }>({
        body: { sourceKey: "website", summary: "Synthetic" },
        context,
        idempotencyKey: "lead-create-synthetic-0001",
        method: "POST",
        path: "/api/v1/leads",
      }),
    ).resolves.toEqual({ leadId: "lead" });

    const [, init] = fetchImplementation.mock.calls[0] ?? [];
    const headers = new Headers(init?.headers);
    expect(headers.get("x-workspace-id")).toBe(context.workspaceId);
    expect(headers.get("idempotency-key")).toBe("lead-create-synthetic-0001");
    expect(JSON.parse(String(init?.body))).not.toHaveProperty("workspaceId");
  });

  it("returns a safe conflict with the server correlation identifier", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>(async () =>
        Response.json(
          { error: { code: "conflict", message: "Safe message" } },
          {
            headers: { "X-Correlation-Id": "server-correlation" },
            status: 409,
          },
        ),
      ),
    );

    await expect(
      requestM3Json({
        body: { expectedVersion: 1 },
        context,
        method: "PATCH",
        path: "/api/v1/leads/id",
      }),
    ).rejects.toMatchObject({
      code: "conflict",
      correlationId: "server-correlation",
      status: 409,
    });
  });

  it("does not expose malformed provider payloads", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>(
        async () => new Response("upstream secret", { status: 503 }),
      ),
    );

    await expect(
      requestM3Json({ context, path: "/api/v1/leads" }),
    ).rejects.toBeInstanceOf(M3ApiError);
  });
});
