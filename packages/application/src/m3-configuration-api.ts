import { z } from "zod";

import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

const uuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());
const checksumSchema = z.string().regex(/^[a-f0-9]{64}$/u);
const semanticVersionSchema = z
  .string()
  .regex(/^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$/u);
const simpleKeySchema = z
  .string()
  .min(1)
  .max(128)
  .regex(/^[a-z][a-z0-9_]{0,127}$/u);
const dottedKeySchema = z
  .string()
  .min(1)
  .max(128)
  .regex(/^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})+$/u);
const definitionKeySchema = z
  .string()
  .min(1)
  .max(128)
  .regex(/^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})*$/u);
const fieldPathSchema = z
  .string()
  .min(1)
  .max(128)
  .regex(/^[a-z][a-z0-9_.-]{0,127}$/u);
const boundedText = (maximum: number) =>
  z
    .string()
    .min(1)
    .max(maximum)
    .refine((value) => value.trim() === value, {
      message: "Text must be canonical and trimmed.",
    });
const reasonSchema = boundedText(2_000);
const positiveVersionSchema = z
  .number()
  .int()
  .min(1)
  .max(Number.MAX_SAFE_INTEGER);
const expectedValueVersionSchema = z
  .number()
  .int()
  .min(0)
  .max(Number.MAX_SAFE_INTEGER);
const timestampSchema = z.iso.datetime({ offset: true });
const nullableTimestampSchema = timestampSchema.nullable();

const localizedLabelSchema = z
  .object({
    en: boundedText(200),
    fr: boundedText(200),
  })
  .strict();
const localizedHelpSchema = z
  .object({
    en: boundedText(2_000),
    fr: boundedText(2_000),
  })
  .strict();

const uniqueFieldPathsSchema = z
  .array(fieldPathSchema)
  .max(100)
  .refine((values) => new Set(values).size === values.length, {
    message: "Required fields must be unique.",
  });
const behaviorFlagsSchema = z
  .record(simpleKeySchema, z.boolean())
  .refine((value) => Object.keys(value).length <= 32, {
    message: "Too many workflow behavior flags.",
  });

const workflowStateSchema = z
  .object({
    behaviorFlags: behaviorFlagsSchema,
    canonicalCategory: z.enum([
      "draft",
      "active",
      "pending",
      "closed",
      "archived",
    ]),
    key: simpleKeySchema,
    labels: localizedLabelSchema,
    requiredFields: uniqueFieldPathsSchema,
    sortOrder: z.number().int().min(-2_147_483_648).max(2_147_483_647),
  })
  .strict();

const guardKeySchema = z
  .enum([
    "required_fields_complete",
    "sale_completion_requirements_met",
    "lead_conversion_requirements_met",
    "lender_approval_recorded",
    "required_documents_generated",
    "completion_requirements_met",
  ])
  .nullable();
const effectKeySchema = z.enum([
  "listing.publish",
  "listing.unpublish",
  "listing.refresh",
  "media.retention_review",
  "lead.follow_up_review",
  "lead.conversion_review",
  "deal.document_readiness_review",
  "deal.inventory_release_review",
]);
const effectKeysSchema = z
  .array(effectKeySchema)
  .max(32)
  .refine((values) => new Set(values).size === values.length, {
    message: "Workflow effects must be unique.",
  });

const workflowTransitionSchema = z
  .object({
    effectKeys: effectKeysSchema,
    fromStateKey: simpleKeySchema,
    guardKey: guardKeySchema,
    key: simpleKeySchema,
    permissionKey: dottedKeySchema,
    reasonRequired: z.boolean(),
    requiredFields: uniqueFieldPathsSchema,
    toStateKey: simpleKeySchema,
  })
  .strict()
  .refine((value) => value.fromStateKey !== value.toStateKey, {
    message: "Workflow transitions must change state.",
  });

const workflowConfigurationSchema = z
  .object({
    definitionKey: definitionKeySchema,
    entityType: z.enum(["inventory_unit", "lead", "deal"]),
    expectedChecksum: checksumSchema,
    expectedLatestVersionId: uuidSchema.nullable(),
    initialStateKey: simpleKeySchema,
    purposeKey: simpleKeySchema,
    reason: reasonSchema,
    schemaVersion: z.number().int().min(1).max(1_000_000),
    semanticVersion: semanticVersionSchema,
    states: z.array(workflowStateSchema).min(1).max(100),
    transitions: z.array(workflowTransitionSchema).max(250),
  })
  .strict()
  .superRefine((value, context) => {
    const stateKeys = new Set(value.states.map((state) => state.key));
    if (stateKeys.size !== value.states.length) {
      context.addIssue({
        code: "custom",
        message: "Workflow state keys must be unique.",
        path: ["states"],
      });
    }
    if (!stateKeys.has(value.initialStateKey)) {
      context.addIssue({
        code: "custom",
        message: "The initial state must exist.",
        path: ["initialStateKey"],
      });
    }
    const transitionKeys = new Set(
      value.transitions.map((transition) => transition.key),
    );
    if (transitionKeys.size !== value.transitions.length) {
      context.addIssue({
        code: "custom",
        message: "Workflow transition keys must be unique.",
        path: ["transitions"],
      });
    }
    value.transitions.forEach((transition, index) => {
      if (
        !stateKeys.has(transition.fromStateKey) ||
        !stateKeys.has(transition.toStateKey)
      ) {
        context.addIssue({
          code: "custom",
          message: "Workflow transitions must reference declared states.",
          path: ["transitions", index],
        });
      }
    });
    const terminal = (state: (typeof value.states)[number]) =>
      state.behaviorFlags.terminal === true ||
      state.canonicalCategory === "closed" ||
      state.canonicalCategory === "archived";
    value.states.forEach((state, index) => {
      const conversionEligible =
        state.behaviorFlags.conversion_eligible === true;
      const conversionTarget = state.behaviorFlags.conversion_target === true;
      const lossTerminal = state.behaviorFlags.loss_terminal === true;
      const cancellation = state.behaviorFlags.cancellation === true;
      if (
        ((conversionEligible || conversionTarget || lossTerminal) &&
          value.entityType !== "lead") ||
        (cancellation && value.entityType !== "deal") ||
        (conversionEligible && terminal(state)) ||
        ((conversionTarget || lossTerminal || cancellation) &&
          !terminal(state)) ||
        (conversionTarget && lossTerminal)
      ) {
        context.addIssue({
          code: "custom",
          message: "Workflow semantic flags do not match the entity lifecycle.",
          path: ["states", index, "behaviorFlags"],
        });
      }
    });
    if (value.entityType === "lead") {
      const conversionTargets = value.states.filter(
        (state) => state.behaviorFlags.conversion_target === true,
      );
      if (conversionTargets.length > 1) {
        context.addIssue({
          code: "custom",
          message: "A lead workflow has at most one conversion target.",
          path: ["states"],
        });
      }
      const conversionTargetKey = conversionTargets[0]?.key;
      value.states.forEach((state, index) => {
        if (state.behaviorFlags.conversion_eligible !== true) return;
        const matches = value.transitions.filter(
          (transition) =>
            transition.fromStateKey === state.key &&
            transition.toStateKey === conversionTargetKey,
        );
        if (conversionTargetKey === undefined || matches.length !== 1) {
          context.addIssue({
            code: "custom",
            message:
              "Each conversion-eligible lead state needs one configured conversion transition.",
            path: ["states", index, "behaviorFlags"],
          });
        }
      });
    }
    value.transitions.forEach((transition, index) => {
      const source = value.states.find(
        (state) => state.key === transition.fromStateKey,
      );
      const target = value.states.find(
        (state) => state.key === transition.toStateKey,
      );
      if (
        (target?.behaviorFlags.conversion_target === true &&
          source?.behaviorFlags.conversion_eligible !== true) ||
        (target?.behaviorFlags.loss_terminal === true &&
          !transition.reasonRequired) ||
        (target?.behaviorFlags.cancellation === true &&
          !transition.reasonRequired)
      ) {
        context.addIssue({
          code: "custom",
          message: "Workflow semantic transition invariants are invalid.",
          path: ["transitions", index],
        });
      }
    });
  });

const workflowApprovalSchema = z
  .object({
    expectedChecksum: checksumSchema,
    expectedRevision: positiveVersionSchema,
    expiresAt: nullableTimestampSchema,
    reason: reasonSchema,
  })
  .strict();
const workflowActivationSchema = z
  .object({
    expectedChecksum: checksumSchema,
    expectedRevision: positiveVersionSchema,
    reason: reasonSchema,
  })
  .strict();

const workflowArtifactSchema = z
  .object({
    entityType: z.enum(["inventory_unit", "lead", "deal"]),
    initialStateKey: simpleKeySchema,
    key: definitionKeySchema,
    purposeKey: simpleKeySchema,
    schemaVersion: z.number().int().min(1).max(1_000_000),
    semanticVersion: semanticVersionSchema,
    states: z.array(workflowStateSchema).min(1).max(100),
    transitions: z.array(workflowTransitionSchema).max(250),
  })
  .strict();
const workflowDefinitionAdminSchema = z
  .object({
    definition: z
      .object({
        createdAt: timestampSchema,
        entityType: z.enum(["inventory_unit", "lead", "deal"]),
        id: uuidSchema,
        key: definitionKeySchema,
        purposeKey: simpleKeySchema,
        status: z.enum(["active", "retired"]),
        workspaceId: uuidSchema,
      })
      .strict(),
    versions: z
      .array(
        z
          .object({
            activatedAt: nullableTimestampSchema,
            approvalCurrent: z.boolean(),
            approvalRecordId: uuidSchema.nullable(),
            approvedAt: nullableTimestampSchema,
            artifact: workflowArtifactSchema,
            checksum: checksumSchema,
            id: uuidSchema,
            retiredAt: nullableTimestampSchema,
            revision: positiveVersionSchema,
            semanticVersion: semanticVersionSchema,
            source: z.enum([
              "configuration",
              "starter_pack",
              "migration_compatibility",
            ]),
            status: z.enum(["draft", "active", "retired"]),
          })
          .strict(),
      )
      .max(100),
  })
  .strict();

const workflowCreateResultSchema = z
  .object({
    auditEventId: uuidSchema,
    checksum: checksumSchema,
    replayed: z.boolean(),
    revision: positiveVersionSchema,
    workflowDefinitionId: uuidSchema,
    workflowVersionId: uuidSchema,
  })
  .strict();
const workflowApprovalResultSchema = workflowCreateResultSchema
  .extend({
    approvalRecordId: uuidSchema,
    approvedAt: timestampSchema,
  })
  .strict();
const workflowActivationResultSchema = workflowCreateResultSchema
  .extend({
    activatedAt: timestampSchema,
    previousActiveVersionId: uuidSchema.nullable(),
  })
  .strict();

const customFieldEntityTypeSchema = z.enum([
  "inventory_unit",
  "party",
  "lead",
  "deal",
  "trade_in",
  "finance_application",
]);
const customFieldValueTypeSchema = z.enum([
  "short_text",
  "long_text",
  "integer",
  "decimal",
  "money",
  "boolean",
  "date",
  "datetime",
  "single_select",
  "multi_select",
  "party_reference",
  "inventory_reference",
  "location_reference",
  "user_reference",
]);
const exactNumericTextSchema = z
  .string()
  .max(60)
  .regex(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/u);
const currencyCodeSchema = z.string().regex(/^[A-Z]{3}$/u);
const moneyValueSchema = z
  .object({
    amountMinor: z
      .string()
      .max(20)
      .regex(/^-?(?:0|[1-9][0-9]*)$/u),
    currencyCode: currencyCodeSchema,
  })
  .strict();
const customFieldValueSchema = z.union([
  z.null(),
  z.boolean(),
  z.string().max(50_000),
  moneyValueSchema,
  z.array(simpleKeySchema).max(100),
]);
const customFieldValidationSchema = z
  .object({
    allowedCurrencies: z
      .array(currencyCodeSchema)
      .max(32)
      .refine((values) => new Set(values).size === values.length)
      .optional(),
    maxItems: z.number().int().min(0).max(100).optional(),
    maxLength: z.number().int().min(0).max(50_000).optional(),
    maximum: exactNumericTextSchema.optional(),
    minItems: z.number().int().min(0).max(100).optional(),
    minLength: z.number().int().min(0).max(50_000).optional(),
    minimum: exactNumericTextSchema.optional(),
    scale: z.number().int().min(0).max(18).optional(),
  })
  .strict()
  .refine(
    (value) =>
      value.minLength === undefined ||
      value.maxLength === undefined ||
      value.minLength <= value.maxLength,
    { message: "Custom field text bounds are invalid." },
  )
  .refine(
    (value) =>
      value.minItems === undefined ||
      value.maxItems === undefined ||
      value.minItems <= value.maxItems,
    { message: "Custom field item bounds are invalid." },
  );
const customFieldOptionSchema = z
  .object({
    active: z.boolean().optional(),
    key: simpleKeySchema,
    labels: localizedLabelSchema,
  })
  .strict();
const customFieldConfigurationSchema = z
  .object({
    checksum: checksumSchema,
    defaultValue: customFieldValueSchema,
    editPermissionKey: dottedKeySchema.nullable(),
    entityType: customFieldEntityTypeSchema,
    fieldKey: simpleKeySchema,
    helpText: localizedHelpSchema,
    labels: localizedLabelSchema,
    options: z
      .array(customFieldOptionSchema)
      .max(100)
      .refine(
        (options) =>
          new Set(options.map((option) => option.key)).size === options.length,
        { message: "Custom field option keys must be unique." },
      ),
    required: z.boolean(),
    searchable: z.boolean(),
    sectionKey: fieldPathSchema,
    sensitive: z.boolean(),
    validation: customFieldValidationSchema,
    valueType: customFieldValueTypeSchema,
    visibilityPermissionKey: dottedKeySchema.nullable(),
  })
  .strict()
  .refine(
    (value) => !value.sensitive || value.visibilityPermissionKey !== null,
    { message: "Sensitive custom fields require visibility permission." },
  )
  .refine(
    (value) =>
      ["single_select", "multi_select"].includes(value.valueType)
        ? value.options.length > 0
        : value.options.length === 0,
    { message: "Custom field options do not match the value type." },
  );
const customFieldActivationSchema = z
  .object({
    expectedChecksum: checksumSchema,
    reason: reasonSchema,
  })
  .strict();
const customFieldValueCommandSchema = z
  .object({
    customFieldVersionId: uuidSchema,
    expectedVersion: expectedValueVersionSchema,
    value: customFieldValueSchema,
  })
  .strict();

const customFieldVersionResultSchema = z
  .object({
    audit_event_id: uuidSchema,
    custom_field_definition_id: uuidSchema,
    custom_field_version_id: uuidSchema,
    replayed: z.boolean(),
    version: positiveVersionSchema,
  })
  .strict();
const customFieldValueResultSchema = z
  .object({
    audit_event_id: uuidSchema,
    custom_field_value_id: uuidSchema,
    replayed: z.boolean(),
    value_version: positiveVersionSchema,
  })
  .strict();
const customFieldValueReadSchema = z
  .object({
    custom_field_definition_id: uuidSchema,
    custom_field_version_id: uuidSchema,
    field_key: simpleKeySchema,
    field_type: customFieldValueTypeSchema,
    help_text: localizedHelpSchema,
    labels: localizedLabelSchema,
    masked: z.boolean(),
    required: z.boolean(),
    searchable: z.boolean(),
    section_key: fieldPathSchema,
    sensitive: z.boolean(),
    value: customFieldValueSchema,
    value_version: positiveVersionSchema.nullable(),
  })
  .strict();

export type M3ConfigurationValidationErrorCode =
  | "invalid_request_body"
  | "invalid_workflow_definition_id"
  | "invalid_workflow_version_id"
  | "invalid_custom_field_definition_id"
  | "invalid_custom_field_version_id"
  | "invalid_custom_field_entity_type"
  | "invalid_entity_id";

export class M3ConfigurationValidationError extends Error {
  readonly code: M3ConfigurationValidationErrorCode;

  constructor(code: M3ConfigurationValidationErrorCode) {
    super("The Milestone 3 configuration request is invalid.");
    this.name = "M3ConfigurationValidationError";
    this.code = code;
  }
}

export class M3ConfigurationRpcContractError extends Error {
  constructor() {
    super("The Milestone 3 configuration store returned an invalid response.");
    this.name = "M3ConfigurationRpcContractError";
  }
}

export interface M3ConfigurationQueryInput {
  readonly accessToken: string;
  readonly workspaceId: string;
}

export interface WorkflowDefinitionQueryInput extends M3ConfigurationQueryInput {
  readonly workflowDefinitionId: string;
}

export interface WorkflowVersionCommandInput extends VerticalSliceCommandInput {
  readonly workflowVersionId: string;
}

export interface CustomFieldVersionCommandInput extends VerticalSliceCommandInput {
  readonly customFieldVersionId: string;
}

export interface CustomFieldValueCommandInput extends VerticalSliceCommandInput {
  readonly customFieldDefinitionId: string;
  readonly entityId: string;
  readonly entityType: string;
}

export interface CustomFieldValuesQueryInput extends M3ConfigurationQueryInput {
  readonly entityId: string;
  readonly entityType: string;
}

function parseBody<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    throw new M3ConfigurationValidationError("invalid_request_body");
  }
  return parsed.data;
}

function parseIdentifier(
  value: unknown,
  code: M3ConfigurationValidationErrorCode,
): string {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) {
    throw new M3ConfigurationValidationError(code);
  }
  return parsed.data;
}

function parseEntityType(
  value: unknown,
): z.infer<typeof customFieldEntityTypeSchema> {
  const parsed = customFieldEntityTypeSchema.safeParse(value);
  if (!parsed.success) {
    throw new M3ConfigurationValidationError(
      "invalid_custom_field_entity_type",
    );
  }
  return parsed.data;
}

function parseObject<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    throw new M3ConfigurationRpcContractError();
  }
  return parsed.data;
}

function parseSingleRow<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = z.array(schema).length(1).safeParse(value);
  if (!parsed.success) {
    throw new M3ConfigurationRpcContractError();
  }
  return parsed.data[0]!;
}

function parseRows<T>(
  schema: z.ZodType<T>,
  maximumRows: number,
  value: unknown,
): readonly T[] {
  const parsed = z.array(schema).max(maximumRows).safeParse(value);
  if (!parsed.success) {
    throw new M3ConfigurationRpcContractError();
  }
  return Object.freeze(parsed.data);
}

function customFieldVersionResult(
  row: z.infer<typeof customFieldVersionResultSchema>,
) {
  return {
    auditEventId: row.audit_event_id,
    customFieldDefinitionId: row.custom_field_definition_id,
    customFieldVersionId: row.custom_field_version_id,
    replayed: row.replayed,
    version: row.version,
  } as const;
}

export class M3ConfigurationApplicationService {
  readonly #gateway: AuthenticatedRpcGateway;

  constructor(gateway: AuthenticatedRpcGateway) {
    this.#gateway = gateway;
  }

  async readWorkflowDefinition(input: WorkflowDefinitionQueryInput) {
    const workflowDefinitionId = parseIdentifier(
      input.workflowDefinitionId,
      "invalid_workflow_definition_id",
    );
    return parseObject(
      workflowDefinitionAdminSchema,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "read_workflow_definition_admin",
        parameters: {
          p_workflow_definition_id: workflowDefinitionId,
          p_workspace_id: input.workspaceId,
        },
      }),
    );
  }

  async createWorkflowVersion(input: VerticalSliceCommandInput) {
    const body = parseBody(workflowConfigurationSchema, input.body);
    return parseObject(
      workflowCreateResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "create_workflow_version_admin",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_definition_key: body.definitionKey,
          p_entity_type: body.entityType,
          p_expected_checksum: body.expectedChecksum,
          p_expected_latest_version_id: body.expectedLatestVersionId,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_initial_state_key: body.initialStateKey,
          p_purpose_key: body.purposeKey,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_schema_version: body.schemaVersion,
          p_semantic_version: body.semanticVersion,
          p_states: body.states,
          p_transitions: body.transitions,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
  }

  async approveWorkflowVersion(input: WorkflowVersionCommandInput) {
    const workflowVersionId = parseIdentifier(
      input.workflowVersionId,
      "invalid_workflow_version_id",
    );
    const body = parseBody(workflowApprovalSchema, input.body);
    return parseObject(
      workflowApprovalResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "approve_workflow_version_admin",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_checksum: body.expectedChecksum,
          p_expected_revision: body.expectedRevision,
          p_expires_at: body.expiresAt,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_workflow_version_id: workflowVersionId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
  }

  async activateWorkflowVersion(input: WorkflowVersionCommandInput) {
    const workflowVersionId = parseIdentifier(
      input.workflowVersionId,
      "invalid_workflow_version_id",
    );
    const body = parseBody(workflowActivationSchema, input.body);
    return parseObject(
      workflowActivationResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "activate_workflow_version_admin",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_checksum: body.expectedChecksum,
          p_expected_revision: body.expectedRevision,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_workflow_version_id: workflowVersionId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
  }

  async createCustomFieldVersion(input: VerticalSliceCommandInput) {
    const body = parseBody(customFieldConfigurationSchema, input.body);
    const row = parseSingleRow(
      customFieldVersionResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "create_custom_field_version",
        parameters: {
          p_checksum: body.checksum,
          p_correlation_id: input.metadata.correlationId,
          p_default_value: body.defaultValue,
          p_edit_permission_key: body.editPermissionKey,
          p_entity_type: body.entityType,
          p_field_key: body.fieldKey,
          p_help_text: body.helpText,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_labels: body.labels,
          p_options: body.options,
          p_request_id: input.metadata.requestId,
          p_required: body.required,
          p_searchable: body.searchable,
          p_section_key: body.sectionKey,
          p_sensitive: body.sensitive,
          p_validation: body.validation,
          p_value_type: body.valueType,
          p_visibility_permission_key: body.visibilityPermissionKey,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return customFieldVersionResult(row);
  }

  async activateCustomFieldVersion(input: CustomFieldVersionCommandInput) {
    const customFieldVersionId = parseIdentifier(
      input.customFieldVersionId,
      "invalid_custom_field_version_id",
    );
    const body = parseBody(customFieldActivationSchema, input.body);
    const row = parseSingleRow(
      customFieldVersionResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "activate_custom_field_version",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_custom_field_version_id: customFieldVersionId,
          p_expected_checksum: body.expectedChecksum,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return customFieldVersionResult(row);
  }

  async setCustomFieldValue(input: CustomFieldValueCommandInput) {
    const customFieldDefinitionId = parseIdentifier(
      input.customFieldDefinitionId,
      "invalid_custom_field_definition_id",
    );
    const entityId = parseIdentifier(input.entityId, "invalid_entity_id");
    const entityType = parseEntityType(input.entityType);
    const body = parseBody(customFieldValueCommandSchema, input.body);
    const row = parseSingleRow(
      customFieldValueResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "set_custom_field_value",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_custom_field_definition_id: customFieldDefinitionId,
          p_custom_field_version_id: body.customFieldVersionId,
          p_entity_id: entityId,
          p_entity_type: entityType,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_request_id: input.metadata.requestId,
          p_value: body.value,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      auditEventId: row.audit_event_id,
      customFieldValueId: row.custom_field_value_id,
      replayed: row.replayed,
      valueVersion: row.value_version,
    } as const;
  }

  async getCustomFieldValues(input: CustomFieldValuesQueryInput) {
    const entityId = parseIdentifier(input.entityId, "invalid_entity_id");
    const entityType = parseEntityType(input.entityType);
    return parseRows(
      customFieldValueReadSchema,
      500,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "get_custom_field_values",
        parameters: {
          p_entity_id: entityId,
          p_entity_type: entityType,
          p_workspace_id: input.workspaceId,
        },
      }),
    ).map((row) => ({
      customFieldDefinitionId: row.custom_field_definition_id,
      customFieldVersionId: row.custom_field_version_id,
      fieldKey: row.field_key,
      fieldType: row.field_type,
      helpText: row.help_text,
      labels: row.labels,
      masked: row.masked,
      required: row.required,
      searchable: row.searchable,
      sectionKey: row.section_key,
      sensitive: row.sensitive,
      value: row.value,
      valueVersion: row.value_version,
    }));
  }
}
