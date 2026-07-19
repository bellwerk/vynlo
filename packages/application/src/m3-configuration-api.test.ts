// Stable test IDs: T-WF-001, T-WF-002, T-WF-003, T-WF-004,
// T-FIELD-001, T-FIELD-002, T-FIELD-003, T-API-001.
import { describe, expect, it } from "vitest";

import {
  type AuthenticatedRpcGateway,
  type AuthenticatedRpcRequest,
} from "./vertical-slice-api";
import {
  M3ConfigurationApplicationService,
  M3ConfigurationRpcContractError,
  M3ConfigurationValidationError,
} from "./m3-configuration-api";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const workflowDefinitionId = "20000000-0000-4000-8000-000000000001";
const workflowVersionId = "30000000-0000-4000-8000-000000000001";
const previousWorkflowVersionId = "30000000-0000-4000-8000-000000000002";
const approvalRecordId = "40000000-0000-4000-8000-000000000001";
const customFieldDefinitionId = "50000000-0000-4000-8000-000000000001";
const customFieldVersionId = "60000000-0000-4000-8000-000000000001";
const customFieldValueId = "70000000-0000-4000-8000-000000000001";
const entityId = "80000000-0000-4000-8000-000000000001";
const auditEventId = "90000000-0000-4000-8000-000000000001";
const correlationId = "a0000000-0000-4000-8000-000000000001";
const checksum = "a".repeat(64);
const timestamp = "2026-07-16T22:00:00.000Z";

const metadata = Object.freeze({
  accessToken: "user.header.signature",
  correlationId,
  idempotencyKey: "m3-configuration-command-0001",
  requestId: "request-m3-configuration-0001",
  workspaceId,
});

const states = Object.freeze([
  {
    behaviorFlags: { terminal: false },
    canonicalCategory: "draft" as const,
    key: "draft",
    labels: { en: "Draft", fr: "Brouillon" },
    requiredFields: [],
    sortOrder: 10,
  },
  {
    behaviorFlags: { terminal: true },
    canonicalCategory: "closed" as const,
    key: "completed",
    labels: { en: "Completed", fr: "Terminé" },
    requiredFields: [],
    sortOrder: 20,
  },
]);

const transitions = Object.freeze([
  {
    effectKeys: [],
    fromStateKey: "draft",
    guardKey: null,
    key: "draft__completed",
    permissionKey: "deals.close",
    reasonRequired: false,
    requiredFields: [],
    toStateKey: "completed",
  },
]);

const workflowBody = Object.freeze({
  definitionKey: "deal.configured",
  entityType: "deal" as const,
  expectedChecksum: checksum,
  expectedLatestVersionId: null,
  initialStateKey: "draft",
  purposeKey: "primary",
  reason: "Create reviewed workflow draft",
  schemaVersion: 1,
  semanticVersion: "1.0.0",
  states,
  transitions,
});

const customFieldBody = Object.freeze({
  checksum,
  defaultValue: null,
  editPermissionKey: "deals.update",
  entityType: "deal" as const,
  fieldKey: "delivery_note",
  helpText: {
    en: "Delivery note shown to staff",
    fr: "Note de livraison affichée au personnel",
  },
  labels: { en: "Delivery note", fr: "Note de livraison" },
  options: [],
  required: false,
  searchable: false,
  sectionKey: "delivery",
  sensitive: false,
  validation: { maxLength: 500 },
  valueType: "long_text" as const,
  visibilityPermissionKey: "deals.read",
});

class RecordingGateway implements AuthenticatedRpcGateway {
  readonly requests: AuthenticatedRpcRequest[] = [];
  readonly #responses: unknown[];

  constructor(...responses: unknown[]) {
    this.#responses = [...responses];
  }

  invoke(request: AuthenticatedRpcRequest): Promise<unknown> {
    this.requests.push(request);
    return Promise.resolve(this.#responses.shift());
  }
}

function workflowArtifact() {
  return {
    entityType: "deal",
    initialStateKey: "draft",
    key: "deal.configured",
    purposeKey: "primary",
    schemaVersion: 1,
    semanticVersion: "1.0.0",
    states,
    transitions,
  };
}

describe("Milestone 3 configuration application API", () => {
  it("T-WF-004 reads one bounded workspace workflow administration model", async () => {
    const gateway = new RecordingGateway({
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
          artifact: workflowArtifact(),
          checksum,
          id: workflowVersionId,
          retiredAt: null,
          revision: 1,
          semanticVersion: "1.0.0",
          source: "configuration",
          status: "draft",
        },
      ],
    });
    const service = new M3ConfigurationApplicationService(gateway);

    await expect(
      service.readWorkflowDefinition({
        accessToken: metadata.accessToken,
        workflowDefinitionId,
        workspaceId,
      }),
    ).resolves.toMatchObject({
      definition: { id: workflowDefinitionId, workspaceId },
      versions: [{ id: workflowVersionId, revision: 1 }],
    });
    expect(gateway.requests).toEqual([
      {
        accessToken: metadata.accessToken,
        functionName: "read_workflow_definition_admin",
        parameters: {
          p_workflow_definition_id: workflowDefinitionId,
          p_workspace_id: workspaceId,
        },
      },
    ]);
  });

  it("T-WF-001 creates an immutable draft with exact checksum and optimistic latest version", async () => {
    const gateway = new RecordingGateway({
      auditEventId,
      checksum,
      replayed: false,
      revision: 1,
      workflowDefinitionId,
      workflowVersionId,
    });
    const service = new M3ConfigurationApplicationService(gateway);

    await expect(
      service.createWorkflowVersion({ body: workflowBody, metadata }),
    ).resolves.toEqual({
      auditEventId,
      checksum,
      replayed: false,
      revision: 1,
      workflowDefinitionId,
      workflowVersionId,
    });
    expect(gateway.requests[0]).toEqual({
      accessToken: metadata.accessToken,
      functionName: "create_workflow_version_admin",
      parameters: {
        p_correlation_id: correlationId,
        p_definition_key: "deal.configured",
        p_entity_type: "deal",
        p_expected_checksum: checksum,
        p_expected_latest_version_id: null,
        p_idempotency_key: metadata.idempotencyKey,
        p_initial_state_key: "draft",
        p_purpose_key: "primary",
        p_reason: "Create reviewed workflow draft",
        p_request_id: metadata.requestId,
        p_schema_version: 1,
        p_semantic_version: "1.0.0",
        p_states: states,
        p_transitions: transitions,
        p_workspace_id: workspaceId,
      },
    });
  });

  it("T-WF-001 rejects unsafe semantic workflow flags before storage", async () => {
    const gateway = new RecordingGateway();
    const service = new M3ConfigurationApplicationService(gateway);
    const unsafeCancellation = {
      ...workflowBody,
      states: [
        states[0],
        {
          ...states[1],
          behaviorFlags: { cancellation: true, terminal: true },
        },
      ],
      transitions: [
        {
          ...transitions[0],
          reasonRequired: false,
        },
      ],
    };

    await expect(
      service.createWorkflowVersion({
        body: unsafeCancellation,
        metadata,
      }),
    ).rejects.toBeInstanceOf(M3ConfigurationValidationError);
    expect(gateway.requests).toEqual([]);
  });

  it("T-WF-003 forwards actor-idempotent approval and activation evidence", async () => {
    const gateway = new RecordingGateway(
      {
        approvalRecordId,
        approvedAt: timestamp,
        auditEventId,
        checksum,
        replayed: false,
        revision: 2,
        workflowDefinitionId,
        workflowVersionId,
      },
      {
        activatedAt: timestamp,
        auditEventId,
        checksum,
        previousActiveVersionId: previousWorkflowVersionId,
        replayed: true,
        revision: 2,
        workflowDefinitionId,
        workflowVersionId,
      },
    );
    const service = new M3ConfigurationApplicationService(gateway);

    await service.approveWorkflowVersion({
      body: {
        expectedChecksum: checksum,
        expectedRevision: 2,
        expiresAt: "2026-08-16T22:00:00.000Z",
        reason: "Reviewed by configuration owner",
      },
      metadata,
      workflowVersionId,
    });
    await expect(
      service.activateWorkflowVersion({
        body: {
          expectedChecksum: checksum,
          expectedRevision: 2,
          reason: "Activate approved workflow",
        },
        metadata,
        workflowVersionId,
      }),
    ).resolves.toMatchObject({
      previousActiveVersionId: previousWorkflowVersionId,
      replayed: true,
    });

    expect(gateway.requests.map((request) => request.functionName)).toEqual([
      "approve_workflow_version_admin",
      "activate_workflow_version_admin",
    ]);
    expect(gateway.requests[0]?.parameters).toMatchObject({
      p_expected_checksum: checksum,
      p_expected_revision: 2,
      p_expires_at: "2026-08-16T22:00:00.000Z",
      p_idempotency_key: metadata.idempotencyKey,
      p_reason: "Reviewed by configuration owner",
      p_workflow_version_id: workflowVersionId,
      p_workspace_id: workspaceId,
    });
    expect(gateway.requests[1]?.parameters).toMatchObject({
      p_expected_checksum: checksum,
      p_expected_revision: 2,
      p_reason: "Activate approved workflow",
      p_workflow_version_id: workflowVersionId,
      p_workspace_id: workspaceId,
    });
  });

  it("T-FIELD-001 creates and activates a typed bilingual custom-field version", async () => {
    const row = {
      audit_event_id: auditEventId,
      custom_field_definition_id: customFieldDefinitionId,
      custom_field_version_id: customFieldVersionId,
      replayed: false,
      version: 1,
    };
    const gateway = new RecordingGateway([row], [{ ...row, replayed: true }]);
    const service = new M3ConfigurationApplicationService(gateway);

    await expect(
      service.createCustomFieldVersion({ body: customFieldBody, metadata }),
    ).resolves.toEqual({
      auditEventId,
      customFieldDefinitionId,
      customFieldVersionId,
      replayed: false,
      version: 1,
    });
    await expect(
      service.activateCustomFieldVersion({
        body: {
          expectedChecksum: checksum,
          reason: "Activate reviewed custom field",
        },
        customFieldVersionId,
        metadata,
      }),
    ).resolves.toMatchObject({ replayed: true });

    expect(gateway.requests[0]).toEqual({
      accessToken: metadata.accessToken,
      functionName: "create_custom_field_version",
      parameters: {
        p_checksum: checksum,
        p_correlation_id: correlationId,
        p_default_value: null,
        p_edit_permission_key: "deals.update",
        p_entity_type: "deal",
        p_field_key: "delivery_note",
        p_help_text: customFieldBody.helpText,
        p_idempotency_key: metadata.idempotencyKey,
        p_labels: customFieldBody.labels,
        p_options: [],
        p_request_id: metadata.requestId,
        p_required: false,
        p_searchable: false,
        p_section_key: "delivery",
        p_sensitive: false,
        p_validation: { maxLength: 500 },
        p_value_type: "long_text",
        p_visibility_permission_key: "deals.read",
        p_workspace_id: workspaceId,
      },
    });
    expect(gateway.requests[1]?.parameters).toMatchObject({
      p_custom_field_version_id: customFieldVersionId,
      p_expected_checksum: checksum,
      p_reason: "Activate reviewed custom field",
    });
  });

  it("M3-FIELD-AC-005 forwards inventory-reference versions without widening the command", async () => {
    const gateway = new RecordingGateway([
      {
        audit_event_id: auditEventId,
        custom_field_definition_id: customFieldDefinitionId,
        custom_field_version_id: customFieldVersionId,
        replayed: false,
        version: 1,
      },
    ]);
    const service = new M3ConfigurationApplicationService(gateway);

    await expect(
      service.createCustomFieldVersion({
        body: {
          ...customFieldBody,
          fieldKey: "related_inventory",
          validation: {},
          valueType: "inventory_reference",
        },
        metadata,
      }),
    ).resolves.toMatchObject({
      customFieldDefinitionId,
      customFieldVersionId,
      replayed: false,
    });

    expect(gateway.requests).toHaveLength(1);
    expect(gateway.requests[0]?.parameters).toMatchObject({
      p_field_key: "related_inventory",
      p_value_type: "inventory_reference",
      p_workspace_id: workspaceId,
    });
    expect(gateway.requests[0]?.parameters).not.toHaveProperty(
      "p_reference_workspace_id",
    );
  });

  it("T-FIELD-002 writes exact values and reads masked projections", async () => {
    const gateway = new RecordingGateway(
      [
        {
          audit_event_id: auditEventId,
          custom_field_value_id: customFieldValueId,
          replayed: false,
          value_version: 2,
        },
      ],
      [
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
      ],
    );
    const service = new M3ConfigurationApplicationService(gateway);

    await expect(
      service.setCustomFieldValue({
        body: {
          customFieldVersionId,
          expectedVersion: 1,
          value: "Deliver after 16:00",
        },
        customFieldDefinitionId,
        entityId,
        entityType: "deal",
        metadata,
      }),
    ).resolves.toEqual({
      auditEventId,
      customFieldValueId,
      replayed: false,
      valueVersion: 2,
    });
    await expect(
      service.getCustomFieldValues({
        accessToken: metadata.accessToken,
        entityId,
        entityType: "deal",
        workspaceId,
      }),
    ).resolves.toEqual([
      {
        customFieldDefinitionId,
        customFieldVersionId,
        fieldKey: "delivery_note",
        fieldType: "long_text",
        helpText: customFieldBody.helpText,
        labels: customFieldBody.labels,
        masked: true,
        required: false,
        searchable: false,
        sectionKey: "delivery",
        sensitive: true,
        value: null,
        valueVersion: 2,
      },
    ]);
    expect(gateway.requests[0]?.parameters).toEqual({
      p_correlation_id: correlationId,
      p_custom_field_definition_id: customFieldDefinitionId,
      p_custom_field_version_id: customFieldVersionId,
      p_entity_id: entityId,
      p_entity_type: "deal",
      p_expected_version: 1,
      p_idempotency_key: metadata.idempotencyKey,
      p_request_id: metadata.requestId,
      p_value: "Deliver after 16:00",
      p_workspace_id: workspaceId,
    });
    expect(gateway.requests[1]).toEqual({
      accessToken: metadata.accessToken,
      functionName: "get_custom_field_values",
      parameters: {
        p_entity_id: entityId,
        p_entity_type: "deal",
        p_workspace_id: workspaceId,
      },
    });
  });

  it("T-FIELD-003 rejects executable-shaped, spoofed, and malformed configuration input", async () => {
    const gateway = new RecordingGateway();
    const service = new M3ConfigurationApplicationService(gateway);

    await expect(
      service.createCustomFieldVersion({
        body: {
          ...customFieldBody,
          validation: { url: "https://tenant.invalid/code" },
          workspaceId,
        },
        metadata,
      }),
    ).rejects.toBeInstanceOf(M3ConfigurationValidationError);
    await expect(
      service.createWorkflowVersion({
        body: {
          ...workflowBody,
          states: [states[0], states[0]],
        },
        metadata,
      }),
    ).rejects.toBeInstanceOf(M3ConfigurationValidationError);
    await expect(
      service.setCustomFieldValue({
        body: {
          customFieldVersionId,
          expectedVersion: 0,
          value: null,
        },
        customFieldDefinitionId,
        entityId,
        entityType: "tenant_script",
        metadata,
      }),
    ).rejects.toMatchObject({
      code: "invalid_custom_field_entity_type",
    });
    expect(gateway.requests).toHaveLength(0);
  });

  it("T-API-001 fails closed on malformed or unbounded RPC responses", async () => {
    const gateway = new RecordingGateway(
      { workflowDefinitionId },
      Array.from({ length: 501 }, () => ({})),
    );
    const service = new M3ConfigurationApplicationService(gateway);

    await expect(
      service.createWorkflowVersion({ body: workflowBody, metadata }),
    ).rejects.toBeInstanceOf(M3ConfigurationRpcContractError);
    await expect(
      service.getCustomFieldValues({
        accessToken: metadata.accessToken,
        entityId,
        entityType: "deal",
        workspaceId,
      }),
    ).rejects.toBeInstanceOf(M3ConfigurationRpcContractError);
  });
});
