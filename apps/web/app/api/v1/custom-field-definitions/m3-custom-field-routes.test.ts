// Stable test IDs: T-FIELD-001, T-FIELD-002, T-FIELD-003, T-API-001.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { PUT as setCustomFieldValue } from "./[id]/values/[entityType]/[entityId]/route";
import { POST as createCustomFieldVersion } from "./route";
import { GET as getCustomFieldValues } from "./values/[entityType]/[entityId]/route";
import { POST as activateCustomFieldVersion } from "./versions/[id]/activation/route";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const customFieldDefinitionId = "20000000-0000-4000-8000-000000000001";
const customFieldVersionId = "30000000-0000-4000-8000-000000000001";
const customFieldValueId = "40000000-0000-4000-8000-000000000001";
const entityId = "50000000-0000-4000-8000-000000000001";
const auditEventId = "60000000-0000-4000-8000-000000000001";
const correlationId = "70000000-0000-4000-8000-000000000001";
const checksum = "b".repeat(64);
const publicProjectKey = "sb_publishable_public_project_key_material";
const userToken = "user.header.signature";

const customFieldBody = {
  checksum,
  defaultValue: null,
  editPermissionKey: "deals.update",
  entityType: "deal",
  fieldKey: "delivery_note",
  helpText: {
    en: "Delivery note shown to staff",
    fr: "Note de livraison pour le personnel",
  },
  labels: { en: "Delivery note", fr: "Note de livraison" },
  options: [],
  required: false,
  searchable: false,
  sectionKey: "delivery",
  sensitive: false,
  validation: { maxLength: 500 },
  valueType: "long_text",
  visibilityPermissionKey: "deals.read",
};

function commandRequest(path: string, body: unknown, method = "POST"): Request {
  return new Request(`http://localhost${path}`, {
    body: JSON.stringify(body),
    headers: {
      Authorization: `Bearer ${userToken}`,
      "Content-Type": "application/json",
      "Idempotency-Key": "m3-custom-field-command-0001",
      "X-Correlation-Id": correlationId,
      "X-Request-Id": "request-m3-custom-field-0001",
      "X-Workspace-Id": workspaceId,
    },
    method,
  });
}

function queryRequest(path: string): Request {
  return new Request(`http://localhost${path}`, {
    headers: {
      Authorization: `Bearer ${userToken}`,
      "X-Correlation-Id": correlationId,
      "X-Request-Id": "request-m3-custom-field-query-0001",
      "X-Workspace-Id": workspaceId,
    },
  });
}

function versionRow(replayed = false) {
  return {
    audit_event_id: auditEventId,
    custom_field_definition_id: customFieldDefinitionId,
    custom_field_version_id: customFieldVersionId,
    replayed,
    version: 1,
  };
}

describe("Milestone 3 custom-field routes", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", publicProjectKey);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("T-FIELD-001 creates and activates one typed bilingual version", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (input) =>
      Response.json([
        versionRow(String(input).endsWith("/activate_custom_field_version")),
      ]),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const createResponse = await createCustomFieldVersion(
      commandRequest("/api/v1/custom-field-definitions", customFieldBody),
    );
    const activationResponse = await activateCustomFieldVersion(
      commandRequest(
        `/api/v1/custom-field-definitions/versions/${customFieldVersionId}/activation`,
        {
          expectedChecksum: checksum,
          reason: "Activate reviewed custom field",
        },
      ),
      { params: Promise.resolve({ id: customFieldVersionId }) },
    );

    expect(createResponse.status).toBe(201);
    expect(activationResponse.status).toBe(200);
    await expect(createResponse.json()).resolves.toMatchObject({
      data: { customFieldDefinitionId, customFieldVersionId },
    });
    const createBody = JSON.parse(
      String(fetchImplementation.mock.calls[0]?.[1]?.body),
    );
    const activationBody = JSON.parse(
      String(fetchImplementation.mock.calls[1]?.[1]?.body),
    );
    expect(createBody).toEqual({
      p_checksum: checksum,
      p_correlation_id: correlationId,
      p_default_value: null,
      p_edit_permission_key: "deals.update",
      p_entity_type: "deal",
      p_field_key: "delivery_note",
      p_help_text: customFieldBody.helpText,
      p_idempotency_key: "m3-custom-field-command-0001",
      p_labels: customFieldBody.labels,
      p_options: [],
      p_request_id: "request-m3-custom-field-0001",
      p_required: false,
      p_searchable: false,
      p_section_key: "delivery",
      p_sensitive: false,
      p_validation: { maxLength: 500 },
      p_value_type: "long_text",
      p_visibility_permission_key: "deals.read",
      p_workspace_id: workspaceId,
    });
    expect(activationBody).toMatchObject({
      p_custom_field_version_id: customFieldVersionId,
      p_expected_checksum: checksum,
      p_reason: "Activate reviewed custom field",
      p_workspace_id: workspaceId,
    });
  });

  it("T-FIELD-002 writes an optimistic value and reads the masked projection", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (input) => {
      if (String(input).endsWith("/set_custom_field_value")) {
        return Response.json([
          {
            audit_event_id: auditEventId,
            custom_field_value_id: customFieldValueId,
            replayed: false,
            value_version: 2,
          },
        ]);
      }
      return Response.json([
        {
          custom_field_definition_id: customFieldDefinitionId,
          custom_field_version_id: customFieldVersionId,
          field_key: "delivery_note",
          field_type: "long_text",
          help_text: customFieldBody.helpText,
          labels: customFieldBody.labels,
          masked: true,
          required: false,
          searchable: false,
          section_key: "delivery",
          sensitive: true,
          value: null,
          value_version: 2,
        },
      ]);
    });
    vi.stubGlobal("fetch", fetchImplementation);

    const setResponse = await setCustomFieldValue(
      commandRequest(
        `/api/v1/custom-field-definitions/${customFieldDefinitionId}/values/deal/${entityId}`,
        {
          customFieldVersionId,
          expectedVersion: 1,
          value: "Deliver after 16:00",
        },
        "PUT",
      ),
      {
        params: Promise.resolve({
          entityId,
          entityType: "deal",
          id: customFieldDefinitionId,
        }),
      },
    );
    const getResponse = await getCustomFieldValues(
      queryRequest(`/api/v1/custom-field-definitions/values/deal/${entityId}`),
      { params: Promise.resolve({ entityId, entityType: "deal" }) },
    );

    expect(setResponse.status).toBe(200);
    expect(getResponse.status).toBe(200);
    await expect(getResponse.json()).resolves.toMatchObject({
      data: [
        {
          customFieldDefinitionId,
          masked: true,
          value: null,
          valueVersion: 2,
        },
      ],
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toEqual({
      p_correlation_id: correlationId,
      p_custom_field_definition_id: customFieldDefinitionId,
      p_custom_field_version_id: customFieldVersionId,
      p_entity_id: entityId,
      p_entity_type: "deal",
      p_expected_version: 1,
      p_idempotency_key: "m3-custom-field-command-0001",
      p_request_id: "request-m3-custom-field-0001",
      p_value: "Deliver after 16:00",
      p_workspace_id: workspaceId,
    });
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[1]?.[1]?.body)),
    ).toEqual({
      p_entity_id: entityId,
      p_entity_type: "deal",
      p_workspace_id: workspaceId,
    });
  });

  it("T-FIELD-003 rejects executable-shaped and spoofed input before PostgREST", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createCustomFieldVersion(
      commandRequest("/api/v1/custom-field-definitions", {
        ...customFieldBody,
        validation: { url: "https://tenant.invalid/script" },
        workspaceId,
      }),
    );

    expect(response.status).toBe(422);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "invalid_request_body" },
    });
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it("T-API-001 rejects invalid entity context without provider access", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await getCustomFieldValues(
      queryRequest("/api/v1/custom-field-definitions/values/script/not-a-uuid"),
      {
        params: Promise.resolve({
          entityId: "not-a-uuid",
          entityType: "script",
        }),
      },
    );

    expect(response.status).toBe(422);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "invalid_entity_id" },
    });
    expect(fetchImplementation).not.toHaveBeenCalled();
  });
});
