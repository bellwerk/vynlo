import { describe, expect, it } from "vitest";

import {
  CustomFieldPolicyError,
  defineCustomFieldVersion,
  normalizeCustomFieldValue,
  planCustomFieldValueMutation,
  projectCustomFieldValue,
  type CustomFieldDefinitionVersion,
} from "./custom-fields";

const WORKSPACE_ID = "10000000-0000-4000-8000-000000000001";
const DEFINITION_ID = "20000000-0000-4000-8000-000000000001";
const VERSION_ID = "30000000-0000-4000-8000-000000000001";
const ENTITY_ID = "40000000-0000-4000-8000-000000000001";
const ACTOR_ID = "50000000-0000-4000-8000-000000000001";
const CORRELATION_ID = "60000000-0000-4000-8000-000000000001";
const VALUE_ID = "70000000-0000-4000-8000-000000000001";

function definitionInput(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: VERSION_ID,
    workspaceId: WORKSPACE_ID,
    definitionId: DEFINITION_ID,
    entityType: "deal",
    key: "customer_reference",
    version: 1,
    checksum: "a".repeat(64),
    type: "short_text",
    labels: { en: "Customer reference", fr: "Référence client" },
    helpText: { en: "Internal reference", fr: "Référence interne" },
    validation: { minLength: 2, maxLength: 30 },
    defaultValue: null,
    options: [],
    required: false,
    visibilityPermissionKey: null,
    editPermissionKey: "deals.update",
    sensitive: false,
    searchable: true,
    sectionKey: "deal.customer",
    status: "active",
    ...overrides,
  };
}

function expectPolicyError(
  operation: () => unknown,
  code: InstanceType<typeof CustomFieldPolicyError>["code"],
): void {
  expect(operation).toThrowError(CustomFieldPolicyError);
  try {
    operation();
  } catch (error) {
    expect(error).toMatchObject({ code });
  }
}

describe("T-FIELD-001 / T-FIELD-002 / T-FIELD-003 M3 typed custom-field contracts", () => {
  it("M3-FIELD-AC-001 copies and deeply freezes a bilingual definition version", () => {
    const input = definitionInput();
    const definition = defineCustomFieldVersion(input);

    (input.labels as Record<string, string>).en = "Changed";
    expect(definition.labels.en).toBe("Customer reference");
    expect(definition.helpText.fr).toBe("Référence interne");
    expect(Object.isFrozen(definition)).toBe(true);
    expect(Object.isFrozen(definition.labels)).toBe(true);
    expect(Object.isFrozen(definition.validation)).toBe(true);
    expect(Object.isFrozen(definition.validation.allowedCurrencies)).toBe(true);
  });

  it("M3-FIELD-AC-001 requires both English and French labels and help", () => {
    expectPolicyError(
      () =>
        defineCustomFieldVersion(
          definitionInput({ labels: { en: "Customer reference" } }),
        ),
      "invalid_localization",
    );
    expectPolicyError(
      () =>
        defineCustomFieldVersion(
          definitionInput({ helpText: { fr: "Référence" } }),
        ),
      "invalid_localization",
    );
  });

  it("M3-FIELD-AC-002 rejects core-field shadowing and executable configuration", () => {
    for (const key of [
      "workspace_id",
      "vin",
      "stock_number",
      "currency_code",
      "official_number",
      "workflow_state",
      "provider_ids",
    ]) {
      expectPolicyError(
        () => defineCustomFieldVersion(definitionInput({ key })),
        "core_field_shadow_not_allowed",
      );
    }

    expectPolicyError(
      () =>
        defineCustomFieldVersion(
          definitionInput({ sql: "select pg_sleep(10)" }),
        ),
      "arbitrary_execution_not_allowed",
    );
    let getterCalled = false;
    const accessorInput = definitionInput();
    Object.defineProperty(accessorInput, "validation", {
      enumerable: true,
      get() {
        getterCalled = true;
        return {};
      },
    });
    expectPolicyError(
      () => defineCustomFieldVersion(accessorInput),
      "arbitrary_execution_not_allowed",
    );
    expect(getterCalled).toBe(false);
  });

  it("M3-FIELD-AC-003 normalizes bounded short and long text", () => {
    const shortText = defineCustomFieldVersion(definitionInput());
    expect(normalizeCustomFieldValue(shortText, "  AB-123  ")).toBe("AB-123");
    expectPolicyError(
      () => normalizeCustomFieldValue(shortText, "x"),
      "value_out_of_range",
    );

    const longText = defineCustomFieldVersion(
      definitionInput({
        type: "long_text",
        validation: { maxLength: 5 },
      }),
    );
    expect(normalizeCustomFieldValue(longText, " notes ")).toBe("notes");
  });

  it("M3-FIELD-AC-003 keeps integer, decimal and money values exact", () => {
    const integer = defineCustomFieldVersion(
      definitionInput({
        type: "integer",
        validation: {
          minimum: "-9223372036854775808",
          maximum: "9223372036854775807",
        },
      }),
    );
    expect(normalizeCustomFieldValue(integer, "9223372036854775807")).toBe(
      "9223372036854775807",
    );
    expectPolicyError(
      () => normalizeCustomFieldValue(integer, "9223372036854775808"),
      "value_out_of_range",
    );
    expectPolicyError(
      () => normalizeCustomFieldValue(integer, 9_007_199_254_740_992),
      "invalid_value",
    );

    const decimal = defineCustomFieldVersion(
      definitionInput({
        type: "decimal",
        validation: { minimum: "-2.5", maximum: "10", scale: 3 },
      }),
    );
    expect(normalizeCustomFieldValue(decimal, "-0.500")).toBe("-0.5");
    expectPolicyError(
      () => normalizeCustomFieldValue(decimal, "10.0001"),
      "value_out_of_range",
    );

    const money = defineCustomFieldVersion(
      definitionInput({
        type: "money",
        validation: { allowedCurrencies: ["CAD", "USD"] },
      }),
    );
    expect(
      normalizeCustomFieldValue(money, {
        amountMinor: "9007199254740993",
        currencyCode: "CAD",
      }),
    ).toEqual({ amountMinor: "9007199254740993", currencyCode: "CAD" });
    expectPolicyError(
      () =>
        normalizeCustomFieldValue(money, {
          amountMinor: "1",
          currencyCode: "EUR",
        }),
      "value_out_of_range",
    );
  });

  it("M3-FIELD-AC-003 validates boolean, real calendar date and RFC3339 datetime", () => {
    const boolean = defineCustomFieldVersion(
      definitionInput({ type: "boolean", validation: {} }),
    );
    expect(normalizeCustomFieldValue(boolean, false)).toBe(false);
    expectPolicyError(
      () => normalizeCustomFieldValue(boolean, "false"),
      "invalid_value",
    );

    const date = defineCustomFieldVersion(
      definitionInput({ type: "date", validation: {} }),
    );
    expect(normalizeCustomFieldValue(date, "2024-02-29")).toBe("2024-02-29");
    expectPolicyError(
      () => normalizeCustomFieldValue(date, "2023-02-29"),
      "invalid_value",
    );

    const datetime = defineCustomFieldVersion(
      definitionInput({ type: "datetime", validation: {} }),
    );
    expect(
      normalizeCustomFieldValue(datetime, "2026-07-16T10:00:00-04:00"),
    ).toBe("2026-07-16T14:00:00.000Z");
  });

  it("M3-FIELD-AC-004 accepts only active declared select options", () => {
    const options = [
      {
        key: "retail",
        labels: { en: "Retail", fr: "Détail" },
        order: 0,
        active: true,
      },
      {
        key: "legacy",
        labels: { en: "Legacy", fr: "Historique" },
        order: 1,
        active: false,
      },
    ];
    const single = defineCustomFieldVersion(
      definitionInput({ type: "single_select", options, validation: {} }),
    );
    expect(normalizeCustomFieldValue(single, "retail")).toBe("retail");
    expectPolicyError(
      () => normalizeCustomFieldValue(single, "legacy"),
      "invalid_option_value",
    );

    const multi = defineCustomFieldVersion(
      definitionInput({
        type: "multi_select",
        options,
        validation: { minItems: 1, maxItems: 2 },
      }),
    );
    expect(normalizeCustomFieldValue(multi, ["retail"])).toEqual(["retail"]);
    expectPolicyError(
      () => normalizeCustomFieldValue(multi, ["retail", "retail"]),
      "value_out_of_range",
    );
  });

  it.each([
    "party_reference",
    "inventory_reference",
    "location_reference",
    "user_reference",
  ])("M3-FIELD-AC-005 validates the %s UUID", (type) => {
    const definition = defineCustomFieldVersion(
      definitionInput({ type, validation: {} }),
    );
    expect(normalizeCustomFieldValue(definition, ENTITY_ID)).toBe(ENTITY_ID);
    expectPolicyError(
      () => normalizeCustomFieldValue(definition, "another-workspace"),
      "invalid_reference",
    );
  });

  it("M3-FIELD-AC-005/007 pins an authorized same-workspace inventory reference", () => {
    const definition = defineCustomFieldVersion(
      definitionInput({
        type: "inventory_reference",
        key: "related_inventory",
        validation: {},
      }),
    );
    const plan = makeMutation(definition, {
      value: ENTITY_ID,
      referenceWorkspaceId: WORKSPACE_ID,
    });

    expect(plan.value).toMatchObject({
      definitionChecksum: "a".repeat(64),
      definitionVersionId: VERSION_ID,
      fieldKey: "related_inventory",
      fieldType: "inventory_reference",
      value: ENTITY_ID,
      version: 1,
      workspaceId: WORKSPACE_ID,
    });
    expect(plan.audit).toMatchObject({
      action: "custom_field_value.created",
      fieldKey: "related_inventory",
      resultingVersion: 1,
    });
    expectPolicyError(
      () =>
        makeMutation(definition, {
          value: ENTITY_ID,
          referenceWorkspaceId: "10000000-0000-4000-8000-000000000002",
        }),
      "workspace_mismatch",
    );
  });

  it("M3-FIELD-AC-006 requires visibility permission for sensitive definitions", () => {
    expectPolicyError(
      () =>
        defineCustomFieldVersion(
          definitionInput({ sensitive: true, visibilityPermissionKey: null }),
        ),
      "invalid_permission_key",
    );

    const definition = defineCustomFieldVersion(
      definitionInput({
        sensitive: true,
        visibilityPermissionKey: "identifiers.read_restricted",
      }),
    );
    const plan = makeMutation(definition);
    expect(
      projectCustomFieldValue({
        definition,
        snapshot: plan.value,
        entityReadable: true,
        effectivePermissionKeys: [],
      }),
    ).toMatchObject({ masked: true, value: null });
    expect(
      projectCustomFieldValue({
        definition,
        snapshot: plan.value,
        entityReadable: true,
        effectivePermissionKeys: ["identifiers.read_restricted"],
      }),
    ).toMatchObject({ masked: false, value: "AB-123" });
    expectPolicyError(
      () =>
        projectCustomFieldValue({
          definition,
          snapshot: plan.value,
          entityReadable: false,
          effectivePermissionKeys: ["identifiers.read_restricted"],
        }),
      "permission_denied",
    );
  });

  it("M3-FIELD-AC-007 pins value, definition version/checksum and audit metadata", () => {
    const definition = defineCustomFieldVersion(definitionInput());
    const plan = makeMutation(definition);

    expect(plan.value).toEqual({
      id: VALUE_ID,
      workspaceId: WORKSPACE_ID,
      entityType: "deal",
      entityId: ENTITY_ID,
      definitionId: DEFINITION_ID,
      definitionVersionId: VERSION_ID,
      definitionVersion: 1,
      definitionChecksum: "a".repeat(64),
      fieldKey: "customer_reference",
      fieldType: "short_text",
      value: "AB-123",
      version: 1,
    });
    expect(plan.audit).toEqual({
      action: "custom_field_value.created",
      actorId: ACTOR_ID,
      correlationId: CORRELATION_ID,
      entityId: ENTITY_ID,
      entityType: "deal",
      fieldKey: "customer_reference",
      previousVersion: null,
      resultingVersion: 1,
      sensitiveValueRedacted: false,
    });
    expect(plan.receipt).toMatchObject({
      actorId: ACTOR_ID,
      idempotencyKey: "field-command-001",
      resultingVersion: 1,
    });
  });

  it("M3-FIELD-AC-008 enforces workspace, entity, permission and expected version", () => {
    const definition = defineCustomFieldVersion(definitionInput());
    const current = makeMutation(definition).value;

    expectPolicyError(
      () =>
        makeMutation(definition, {
          workspaceId: "10000000-0000-4000-8000-000000000002",
        }),
      "workspace_mismatch",
    );
    expectPolicyError(
      () => makeMutation(definition, { entityType: "lead" }),
      "entity_mismatch",
    );
    expectPolicyError(
      () => makeMutation(definition, { entityWritable: false }),
      "permission_denied",
    );
    expectPolicyError(
      () => makeMutation(definition, { effectivePermissionKeys: [] }),
      "permission_denied",
    );
    expectPolicyError(
      () =>
        makeMutation(definition, {
          referenceWorkspaceId: "10000000-0000-4000-8000-000000000002",
        }),
      "workspace_mismatch",
    );
    expectPolicyError(
      () => makeMutation(definition, { current, expectedVersion: 0 }),
      "expected_version_conflict",
    );

    expect(
      makeMutation(definition, {
        current,
        expectedVersion: 1,
        value: "CD-456",
      }),
    ).toMatchObject({
      value: { value: "CD-456", version: 2 },
      audit: { action: "custom_field_value.updated", previousVersion: 1 },
    });
  });

  it("M3-FIELD-AC-009 rejects writes through a draft or retired version", () => {
    for (const status of ["draft", "retired"] as const) {
      const definition = defineCustomFieldVersion(definitionInput({ status }));
      expectPolicyError(() => makeMutation(definition), "inactive_definition");
    }
  });
});

function makeMutation(
  definition: CustomFieldDefinitionVersion,
  overrides: Record<string, unknown> = {},
) {
  return planCustomFieldValueMutation({
    definition,
    current: null,
    valueId: VALUE_ID,
    workspaceId: WORKSPACE_ID,
    entityType: "deal",
    entityId: ENTITY_ID,
    referenceWorkspaceId: WORKSPACE_ID,
    expectedVersion: 0,
    entityWritable: true,
    effectivePermissionKeys: ["deals.update"],
    value: "AB-123",
    actorId: ACTOR_ID,
    correlationId: CORRELATION_ID,
    idempotencyKey: "field-command-001",
    ...overrides,
  });
}
