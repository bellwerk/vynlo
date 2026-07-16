// Stable test IDs: T-API-001, T-TEN-002.
import { describe, expect, it } from "vitest";
import {
  MAX_COMMAND_BODY_BYTES,
  parseCommandMetadata,
  readCommandJson,
} from "./command-route";

const validHeaders = Object.freeze({
  Authorization: "Bearer user.header.signature",
  "Content-Type": "application/json; charset=utf-8",
  "Idempotency-Key": "command-key-0001",
  "X-Correlation-Id": "00000000-0000-4000-8000-000000000002",
  "X-Request-Id": "request-0001",
  "X-Workspace-Id": "00000000-0000-4000-8000-000000000001",
});

function requestWith(
  body: BodyInit | null,
  headers: HeadersInit = validHeaders,
): Request {
  return new Request("http://localhost/api/v1/parties", {
    body,
    headers,
    method: "POST",
  });
}

describe("command request boundary", () => {
  it("validates and extracts authoritative headers", () => {
    expect(parseCommandMetadata(requestWith("{}"))).toEqual({
      accessToken: "user.header.signature",
      correlationId: "00000000-0000-4000-8000-000000000002",
      idempotencyKey: "command-key-0001",
      requestId: "request-0001",
      workspaceId: "00000000-0000-4000-8000-000000000001",
    });
  });

  it.each([
    ["authorization", "Bearer not-a-jwt", "authentication_required", 401],
    ["x-workspace-id", "not-a-uuid", "invalid_workspace", 400],
    ["idempotency-key", "short", "invalid_idempotency_key", 400],
    ["x-request-id", "request id with spaces", "invalid_request_id", 400],
    ["x-correlation-id", "not-a-uuid", "invalid_correlation_id", 400],
  ])(
    "rejects malformed %s before reading the body",
    (header, value, code, status) => {
      const headers = new Headers(validHeaders);
      headers.set(header, value);
      expect(() => parseCommandMetadata(requestWith("{}", headers))).toThrow(
        expect.objectContaining({ code, status }),
      );
    },
  );

  it("parses JSON as unknown and rejects malformed or unsupported bodies", async () => {
    await expect(
      readCommandJson(requestWith('{"displayName":"Alice"}')),
    ).resolves.toEqual({ displayName: "Alice" });
    await expect(readCommandJson(requestWith("{"))).rejects.toMatchObject({
      code: "invalid_json",
      status: 400,
    });
    await expect(
      readCommandJson(
        requestWith("{}", {
          ...validHeaders,
          "Content-Type": "text/plain",
        }),
      ),
    ).rejects.toMatchObject({ code: "invalid_content_type", status: 400 });
  });

  it("fails before allocation for declared and streamed oversized bodies", async () => {
    const declaredHeaders = new Headers(validHeaders);
    declaredHeaders.set("Content-Length", String(MAX_COMMAND_BODY_BYTES + 1));
    await expect(
      readCommandJson(requestWith("{}", declaredHeaders)),
    ).rejects.toMatchObject({ code: "request_body_too_large", status: 400 });

    await expect(
      readCommandJson(requestWith(`"${"x".repeat(MAX_COMMAND_BODY_BYTES)}"`)),
    ).rejects.toMatchObject({ code: "request_body_too_large", status: 400 });
  });
});
