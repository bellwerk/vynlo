// Stable test IDs: T-WF-001, T-WF-002, T-WF-003, T-WF-004, T-API-001.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { POST as activateWorkflowVersion } from "../workflow-versions/[id]/activation/route";
import { POST as approveWorkflowVersion } from "../workflow-versions/[id]/approval/route";
import { POST as createWorkflowVersion } from "../workflow-versions/route";
import { GET as readWorkflowDefinition } from "./[id]/route";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const workflowDefinitionId = "20000000-0000-4000-8000-000000000001";
const workflowVersionId = "30000000-0000-4000-8000-000000000001";
const approvalRecordId = "40000000-0000-4000-8000-000000000001";
const auditEventId = "50000000-0000-4000-8000-000000000001";
const correlationId = "60000000-0000-4000-8000-000000000001";
const checksum = "a".repeat(64);
const timestamp = "2026-07-16T22:00:00.000Z";
const publicProjectKey = "sb_publishable_public_project_key_material";
const userToken = "user.header.signature";

const states = [
  {
    behaviorFlags: { terminal: false },
    canonicalCategory: "draft",
    key: "draft",
    labels: { en: "Draft", fr: "Brouillon" },
    requiredFields: [],
    sortOrder: 10,
  },
];
const workflowBody = {
  definitionKey: "deal.configured",
  entityType: "deal",
  expectedChecksum: checksum,
  expectedLatestVersionId: null,
  initialStateKey: "draft",
  purposeKey: "primary",
  reason: "Create reviewed workflow draft",
  schemaVersion: 1,
  semanticVersion: "1.0.0",
  states,
  transitions: [],
};

function commandRequest(path: string, body: unknown): Request {
  return new Request(`http://localhost${path}`, {
    body: JSON.stringify(body),
    headers: {
      Authorization: `Bearer ${userToken}`,
      "Content-Type": "application/json",
      "Idempotency-Key": "m3-workflow-command-0001",
      "X-Correlation-Id": correlationId,
      "X-Request-Id": "request-m3-workflow-0001",
      "X-Workspace-Id": workspaceId,
    },
    method: "POST",
  });
}

function queryRequest(path: string): Request {
  return new Request(`http://localhost${path}`, {
    headers: {
      Authorization: `Bearer ${userToken}`,
      "X-Correlation-Id": correlationId,
      "X-Request-Id": "request-m3-workflow-query-0001",
      "X-Workspace-Id": workspaceId,
    },
  });
}

function workflowResult(replayed = false) {
  return {
    auditEventId,
    checksum,
    replayed,
    revision: 1,
    workflowDefinitionId,
    workflowVersionId,
  };
}

describe("Milestone 3 workflow configuration routes", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", publicProjectKey);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("T-WF-004 reads the bounded workspace administration projection", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json({
        definition: {
          createdAt: timestamp,
          entityType: "deal",
          id: workflowDefinitionId,
          key: "deal.configured",
          purposeKey: "primary",
          status: "active",
          workspaceId,
        },
        versions: [
          {
            activatedAt: null,
            approvalCurrent: false,
            approvalRecordId: null,
            approvedAt: null,
            artifact: {
              entityType: "deal",
              initialStateKey: "draft",
              key: "deal.configured",
              purposeKey: "primary",
              schemaVersion: 1,
              semanticVersion: "1.0.0",
              states,
              transitions: [],
            },
            checksum,
            id: workflowVersionId,
            retiredAt: null,
            revision: 1,
            semanticVersion: "1.0.0",
            source: "configuration",
            status: "draft",
          },
        ],
      }),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await readWorkflowDefinition(
      queryRequest(`/api/v1/workflow-definitions/${workflowDefinitionId}`),
      { params: Promise.resolve({ id: workflowDefinitionId }) },
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      data: {
        definition: { id: workflowDefinitionId, workspaceId },
        versions: [{ id: workflowVersionId }],
      },
    });
    const [url, init] = fetchImplementation.mock.calls[0] ?? [];
    expect(url).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/read_workflow_definition_admin",
    );
    expect(JSON.parse(String(init?.body))).toEqual({
      p_workflow_definition_id: workflowDefinitionId,
      p_workspace_id: workspaceId,
    });
  });

  it("T-WF-001 creates an immutable draft using exact actor idempotency and checksum inputs", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(workflowResult()),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createWorkflowVersion(
      commandRequest("/api/v1/workflow-versions", workflowBody),
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toMatchObject({
      data: { replayed: false, workflowVersionId },
    });
    const [url, init] = fetchImplementation.mock.calls[0] ?? [];
    expect(url).toBe(
      "http://127.0.0.1:54321/rest/v1/rpc/create_workflow_version_admin",
    );
    expect(JSON.parse(String(init?.body))).toEqual({
      p_correlation_id: correlationId,
      p_definition_key: "deal.configured",
      p_entity_type: "deal",
      p_expected_checksum: checksum,
      p_expected_latest_version_id: null,
      p_idempotency_key: "m3-workflow-command-0001",
      p_initial_state_key: "draft",
      p_purpose_key: "primary",
      p_reason: "Create reviewed workflow draft",
      p_request_id: "request-m3-workflow-0001",
      p_schema_version: 1,
      p_semantic_version: "1.0.0",
      p_states: states,
      p_transitions: [],
      p_workspace_id: workspaceId,
    });
    const headers = new Headers(init?.headers);
    expect(headers.get("authorization")).toBe(`Bearer ${userToken}`);
    expect(headers.get("apikey")).toBe(publicProjectKey);
    expect(headers.get("content-profile")).toBe("app");
    expect(headers.get("x-workspace-id")).toBeNull();
  });

  it("T-WF-002 / T-WF-003 approves then activates exact reviewed revisions", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (input) =>
      String(input).endsWith("/approve_workflow_version_admin")
        ? Response.json({
            ...workflowResult(),
            approvalRecordId,
            approvedAt: timestamp,
          })
        : Response.json({
            ...workflowResult(true),
            activatedAt: timestamp,
            previousActiveVersionId: null,
          }),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const approvalResponse = await approveWorkflowVersion(
      commandRequest(
        `/api/v1/workflow-versions/${workflowVersionId}/approval`,
        {
          expectedChecksum: checksum,
          expectedRevision: 1,
          expiresAt: "2026-08-16T22:00:00.000Z",
          reason: "Reviewed by configuration owner",
        },
      ),
      { params: Promise.resolve({ id: workflowVersionId }) },
    );
    const activationResponse = await activateWorkflowVersion(
      commandRequest(
        `/api/v1/workflow-versions/${workflowVersionId}/activation`,
        {
          expectedChecksum: checksum,
          expectedRevision: 1,
          reason: "Activate approved workflow",
        },
      ),
      { params: Promise.resolve({ id: workflowVersionId }) },
    );

    expect(approvalResponse.status).toBe(200);
    expect(activationResponse.status).toBe(200);
    const approvalBody = JSON.parse(
      String(fetchImplementation.mock.calls[0]?.[1]?.body),
    );
    const activationBody = JSON.parse(
      String(fetchImplementation.mock.calls[1]?.[1]?.body),
    );
    expect(approvalBody).toMatchObject({
      p_expected_checksum: checksum,
      p_expected_revision: 1,
      p_expires_at: "2026-08-16T22:00:00.000Z",
      p_reason: "Reviewed by configuration owner",
      p_workflow_version_id: workflowVersionId,
    });
    expect(activationBody).toMatchObject({
      p_expected_checksum: checksum,
      p_expected_revision: 1,
      p_reason: "Activate approved workflow",
      p_workflow_version_id: workflowVersionId,
    });
  });

  it("T-API-001 rejects path/body authority and fails closed on malformed results", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json({ workflowVersionId }),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const invalidResponse = await approveWorkflowVersion(
      commandRequest("/api/v1/workflow-versions/not-a-uuid/approval", {
        expectedChecksum: checksum,
        expectedRevision: 1,
        expiresAt: null,
        reason: "reviewed",
        workspaceId,
      }),
      { params: Promise.resolve({ id: "not-a-uuid" }) },
    );
    expect(invalidResponse.status).toBe(422);
    await expect(invalidResponse.json()).resolves.toMatchObject({
      error: { code: "invalid_workflow_version_id" },
    });
    expect(fetchImplementation).not.toHaveBeenCalled();

    const contractResponse = await createWorkflowVersion(
      commandRequest("/api/v1/workflow-versions", workflowBody),
    );
    expect(contractResponse.status).toBe(503);
    await expect(contractResponse.json()).resolves.toMatchObject({
      error: { code: "service_unavailable" },
    });
  });
});
