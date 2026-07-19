import { describe, expect, it } from "vitest";

import {
  WorkflowPolicyError,
  defineVersionedWorkflow,
  executeWorkflowTransition,
  type WorkflowInstanceSnapshot,
} from "./versioned-workflow";

const CHECKSUM = "a".repeat(64);

function makeDefinitionInput() {
  return {
    key: "starter_inventory",
    entityType: "inventory_unit",
    version: "1.0.0",
    checksum: CHECKSUM,
    initialStateKey: "draft",
    states: [
      {
        key: "draft",
        category: "draft",
        labels: { en: "Draft", fr: "Brouillon" },
        flags: { publishable: false },
        requiredFields: [],
      },
      {
        key: "ready",
        category: "active",
        labels: { en: "Ready", fr: "Prêt" },
        flags: { publishable: true },
        requiredFields: ["location_id"],
      },
      {
        key: "sold",
        category: "closed",
        labels: { en: "Sold", fr: "Vendu" },
        flags: { terminal: true },
        requiredFields: [],
      },
    ],
    transitions: [
      {
        key: "mark_ready",
        fromStateKey: "draft",
        toStateKey: "ready",
        permissionKey: "inventory.transition",
        guardKey: "required_fields_complete",
        reasonRequired: false,
        requiredFields: ["vin"],
        effectKeys: ["listing.publish", "listing.refresh"],
      },
      {
        key: "complete_sale",
        fromStateKey: "ready",
        toStateKey: "sold",
        permissionKey: "inventory.transition",
        guardKey: "sale_completion_requirements_met",
        reasonRequired: true,
        requiredFields: [],
        effectKeys: ["listing.unpublish", "media.retention_review"],
      },
    ],
  };
}

function makeLeadDefinitionInput() {
  return {
    checksum: CHECKSUM,
    entityType: "lead",
    initialStateKey: "review_ready",
    key: "configured_lead",
    states: [
      {
        category: "active",
        flags: { conversion_eligible: true, terminal: false },
        key: "review_ready",
        labels: { en: "Ready", fr: "Prêt" },
        requiredFields: [],
      },
      {
        category: "closed",
        flags: { conversion_target: true, terminal: true },
        key: "won",
        labels: { en: "Won", fr: "Gagné" },
        requiredFields: [],
      },
      {
        category: "closed",
        flags: { loss_terminal: true, terminal: true },
        key: "deferred",
        labels: { en: "Deferred", fr: "Reporté" },
        requiredFields: [],
      },
    ],
    transitions: [
      {
        effectKeys: [],
        fromStateKey: "review_ready",
        guardKey: "lead_conversion_requirements_met",
        key: "complete_conversion",
        permissionKey: "deals.create",
        reasonRequired: false,
        requiredFields: [],
        toStateKey: "won",
      },
      {
        effectKeys: [],
        fromStateKey: "review_ready",
        guardKey: null,
        key: "defer_lead",
        permissionKey: "crm.update",
        reasonRequired: true,
        requiredFields: [],
        toStateKey: "deferred",
      },
    ],
    version: "1.0.0",
  };
}

function expectPolicyError(
  operation: () => unknown,
  code: InstanceType<typeof WorkflowPolicyError>["code"],
): void {
  expect(operation).toThrowError(WorkflowPolicyError);
  try {
    operation();
  } catch (error) {
    expect(error).toMatchObject({ code });
  }
}

const INSTANCE: WorkflowInstanceSnapshot = {
  id: "workflow-instance-001",
  entityId: "inventory-unit-001",
  definitionKey: "starter_inventory",
  definitionVersion: "1.0.0",
  definitionChecksum: CHECKSUM,
  currentStateKey: "draft",
  canonicalCategory: "draft",
  version: 3,
};

describe("T-CFG-004 / T-INV-004 M2 immutable versioned workflow contracts", () => {
  it("M2-WF-AC-001 freezes copied definitions, states, transitions and declarations", () => {
    const input = makeDefinitionInput();
    const definition = defineVersionedWorkflow(input);

    input.states[0]!.labels.en = "Changed after validation";
    input.transitions[0]!.effectKeys.push("listing.unpublish");

    expect(definition.states[0]?.labels.en).toBe("Draft");
    expect(definition.transitions[0]?.effectKeys).toEqual([
      "listing.publish",
      "listing.refresh",
    ]);
    expect(Object.isFrozen(definition)).toBe(true);
    expect(Object.isFrozen(definition.states)).toBe(true);
    expect(Object.isFrozen(definition.states[0])).toBe(true);
    expect(Object.isFrozen(definition.states[0]?.labels)).toBe(true);
    expect(Object.isFrozen(definition.transitions[0]?.effectKeys)).toBe(true);
    expect(() =>
      Object.assign(definition.transitions[0]!, { toStateKey: "draft" }),
    ).toThrow(TypeError);
  });

  it("M2-WF-AC-001 rejects duplicate, missing and terminal transition graph edges", () => {
    const duplicateState = makeDefinitionInput();
    duplicateState.states.push({ ...duplicateState.states[0]! });
    expectPolicyError(
      () => defineVersionedWorkflow(duplicateState),
      "duplicate_state_key",
    );

    const missingState = makeDefinitionInput();
    missingState.transitions[0]!.toStateKey = "missing";
    expectPolicyError(
      () => defineVersionedWorkflow(missingState),
      "transition_state_missing",
    );

    const terminalEdge = makeDefinitionInput();
    terminalEdge.transitions.push({
      ...terminalEdge.transitions[0]!,
      key: "reopen",
      fromStateKey: "sold",
      toStateKey: "ready",
    });
    expectPolicyError(
      () => defineVersionedWorkflow(terminalEdge),
      "terminal_state_has_transition",
    );
  });

  it("M2-WF-AC-002 accepts only the finite declarative guard and effect catalogs", () => {
    const scriptedGuard = makeDefinitionInput();
    scriptedGuard.transitions[0]!.guardKey = "javascript";
    expectPolicyError(
      () => defineVersionedWorkflow(scriptedGuard),
      "unsupported_guard_key",
    );

    const networkEffect = makeDefinitionInput();
    networkEffect.transitions[0]!.effectKeys = ["network.request"];
    expectPolicyError(
      () => defineVersionedWorkflow(networkEffect),
      "unsupported_effect_key",
    );

    const sqlDefinition = {
      ...makeDefinitionInput(),
      sql: "select pg_sleep(10)",
    };
    expectPolicyError(
      () => defineVersionedWorkflow(sqlDefinition),
      "arbitrary_execution_not_allowed",
    );

    let getterCalled = false;
    const getterTransition = { ...makeDefinitionInput().transitions[0]! };
    Object.defineProperty(getterTransition, "guardKey", {
      enumerable: true,
      get() {
        getterCalled = true;
        return "required_fields_complete";
      },
    });
    const accessorDefinition = makeDefinitionInput();
    accessorDefinition.transitions = [
      getterTransition,
      accessorDefinition.transitions[1]!,
    ];
    expectPolicyError(
      () => defineVersionedWorkflow(accessorDefinition),
      "arbitrary_execution_not_allowed",
    );
    expect(getterCalled).toBe(false);

    const validated = defineVersionedWorkflow(makeDefinitionInput());
    const forgedDefinition = {
      ...validated,
      transitions: [
        {
          ...validated.transitions[0]!,
          effectKeys: ["network.request"],
        },
        validated.transitions[1]!,
      ],
    };
    expectPolicyError(
      () =>
        executeWorkflowTransition({
          definition: forgedDefinition as never,
          instance: INSTANCE,
          transitionKey: "mark_ready",
          expectedVersion: 3,
          effectivePermissionKeys: ["inventory.transition"],
          fields: {
            vin: "1HGCM82633A004352",
            location_id: "location-001",
          },
          guardResults: { required_fields_complete: true },
          eventId: "workflow-event-001",
          actorId: "user-001",
          correlationId: "correlation-001",
          occurredAt: "2026-07-16T14:00:00Z",
        }),
      "unsupported_effect_key",
    );
  });

  it("M3-WF-AC-001 validates configured lead semantics without state-name coupling", () => {
    expect(defineVersionedWorkflow(makeLeadDefinitionInput())).toMatchObject({
      entityType: "lead",
      initialStateKey: "review_ready",
    });

    const nonTerminalTarget = makeLeadDefinitionInput();
    nonTerminalTarget.states[1]!.category = "active";
    nonTerminalTarget.states[1]!.flags.terminal = false;
    expectPolicyError(
      () => defineVersionedWorkflow(nonTerminalTarget),
      "invalid_definition",
    );

    const ineligibleSource = makeLeadDefinitionInput();
    ineligibleSource.states[0]!.flags.conversion_eligible = false;
    expectPolicyError(
      () => defineVersionedWorkflow(ineligibleSource),
      "invalid_definition",
    );

    const unreasonedLoss = makeLeadDefinitionInput();
    unreasonedLoss.transitions[1]!.reasonRequired = false;
    expectPolicyError(
      () => defineVersionedWorkflow(unreasonedLoss),
      "invalid_definition",
    );
  });

  it("M2-WF-AC-003 enforces permission, required fields, guards and expected version", () => {
    const definition = defineVersionedWorkflow(makeDefinitionInput());
    const command = {
      definition,
      instance: INSTANCE,
      transitionKey: "mark_ready",
      expectedVersion: 3,
      effectivePermissionKeys: ["inventory.transition"],
      fields: {
        vin: "1HGCM82633A004352",
        location_id: "location-001",
      },
      guardResults: { required_fields_complete: true },
      eventId: "workflow-event-001",
      actorId: "user-001",
      correlationId: "correlation-001",
      occurredAt: "2026-07-16T10:00:00-04:00",
    } as const;

    expectPolicyError(
      () =>
        executeWorkflowTransition({
          ...command,
          effectivePermissionKeys: [],
        }),
      "permission_denied",
    );
    expectPolicyError(
      () =>
        executeWorkflowTransition({
          ...command,
          expectedVersion: 2,
        }),
      "expected_version_conflict",
    );
    expectPolicyError(
      () =>
        executeWorkflowTransition({
          ...command,
          fields: { location_id: "location-001" },
        }),
      "required_field_missing",
    );
    expectPolicyError(
      () =>
        executeWorkflowTransition({
          ...command,
          guardResults: { required_fields_complete: false },
        }),
      "guard_rejected",
    );
  });

  it("M2-WF-AC-004 returns deterministic pinned instance, workflow and outbox events", () => {
    const definition = defineVersionedWorkflow(makeDefinitionInput());
    const command = {
      definition,
      instance: INSTANCE,
      transitionKey: "mark_ready",
      expectedVersion: 3,
      effectivePermissionKeys: ["inventory.transition"],
      fields: {
        vin: "1HGCM82633A004352",
        location_id: "location-001",
      },
      guardResults: { required_fields_complete: true },
      eventId: "workflow-event-001",
      actorId: "user-001",
      correlationId: "correlation-001",
      occurredAt: "2026-07-16T10:00:00-04:00",
    } as const;

    const first = executeWorkflowTransition(command);
    const replayPlan = executeWorkflowTransition(command);

    expect(first).toEqual(replayPlan);
    expect(first).toEqual({
      instance: {
        ...INSTANCE,
        currentStateKey: "ready",
        canonicalCategory: "active",
        version: 4,
      },
      workflowEvent: {
        id: "workflow-event-001",
        instanceId: "workflow-instance-001",
        entityType: "inventory_unit",
        entityId: "inventory-unit-001",
        definitionKey: "starter_inventory",
        definitionVersion: "1.0.0",
        definitionChecksum: CHECKSUM,
        transitionKey: "mark_ready",
        fromStateKey: "draft",
        fromCategory: "draft",
        toStateKey: "ready",
        toCategory: "active",
        actorId: "user-001",
        reason: null,
        inputSnapshot: {
          requiredFieldKeys: ["vin", "location_id"],
          guardKey: "required_fields_complete",
          guardSatisfied: true,
          reasonProvided: false,
        },
        effectSnapshot: {
          effectKeys: ["listing.publish", "listing.refresh"],
        },
        previousVersion: 3,
        resultingVersion: 4,
        correlationId: "correlation-001",
        occurredAt: "2026-07-16T14:00:00.000Z",
      },
      outboxEvent: {
        idempotencyKey: "workflow-event-001:transitioned",
        eventType: "inventory_unit.transitioned",
        aggregateType: "inventory_unit",
        aggregateId: "inventory-unit-001",
        aggregateVersion: 4,
        workflowEventId: "workflow-event-001",
        transitionKey: "mark_ready",
        fromStateKey: "draft",
        toStateKey: "ready",
        canonicalCategory: "active",
        effectKeys: ["listing.publish", "listing.refresh"],
        correlationId: "correlation-001",
        occurredAt: "2026-07-16T14:00:00.000Z",
      },
    });
    expect(INSTANCE).toMatchObject({ currentStateKey: "draft", version: 3 });
    expect(Object.isFrozen(first.outboxEvent.effectKeys)).toBe(true);
    expect(Object.isFrozen(first.workflowEvent.inputSnapshot)).toBe(true);
    expect(
      Object.isFrozen(first.workflowEvent.inputSnapshot.requiredFieldKeys),
    ).toBe(true);
    expect(Object.isFrozen(first.workflowEvent.effectSnapshot)).toBe(true);
    expect(Object.isFrozen(first.workflowEvent.effectSnapshot.effectKeys)).toBe(
      true,
    );
  });

  it("M2-WF-AC-005 requires a reason and explicit successful sale guard", () => {
    const definition = defineVersionedWorkflow(makeDefinitionInput());
    const instance: WorkflowInstanceSnapshot = {
      ...INSTANCE,
      currentStateKey: "ready",
      canonicalCategory: "active",
      version: 4,
    };
    const command = {
      definition,
      instance,
      transitionKey: "complete_sale",
      expectedVersion: 4,
      effectivePermissionKeys: ["inventory.transition"],
      fields: {},
      guardResults: { sale_completion_requirements_met: true },
      eventId: "workflow-event-002",
      actorId: "user-001",
      correlationId: "correlation-002",
      occurredAt: "2026-07-16T15:00:00Z",
    } as const;

    expectPolicyError(
      () => executeWorkflowTransition(command),
      "reason_required",
    );
    expectPolicyError(
      () =>
        executeWorkflowTransition({
          ...command,
          reason: "Completed synthetic sale.",
          guardResults: { sale_completion_requirements_met: false },
        }),
      "guard_rejected",
    );

    expect(
      executeWorkflowTransition({
        ...command,
        reason: "  Completed synthetic sale.  ",
      }),
    ).toMatchObject({
      instance: { currentStateKey: "sold", canonicalCategory: "closed" },
      workflowEvent: { reason: "Completed synthetic sale." },
      outboxEvent: {
        effectKeys: ["listing.unpublish", "media.retention_review"],
      },
    });
  });

  it("M2-WF-AC-006 rejects a different version, checksum or canonical state snapshot", () => {
    const definition = defineVersionedWorkflow(makeDefinitionInput());
    const base = {
      definition,
      instance: INSTANCE,
      transitionKey: "mark_ready",
      expectedVersion: 3,
      effectivePermissionKeys: ["inventory.transition"],
      fields: { vin: "1HGCM82633A004352", location_id: "location-001" },
      guardResults: { required_fields_complete: true },
      eventId: "workflow-event-001",
      actorId: "user-001",
      correlationId: "correlation-001",
      occurredAt: "2026-07-16T14:00:00Z",
    } as const;

    expectPolicyError(
      () =>
        executeWorkflowTransition({
          ...base,
          instance: { ...INSTANCE, definitionVersion: "1.0.1" },
        }),
      "instance_definition_mismatch",
    );
    expectPolicyError(
      () =>
        executeWorkflowTransition({
          ...base,
          instance: { ...INSTANCE, definitionChecksum: "b".repeat(64) },
        }),
      "instance_definition_mismatch",
    );
    expectPolicyError(
      () =>
        executeWorkflowTransition({
          ...base,
          instance: { ...INSTANCE, canonicalCategory: "active" },
        }),
      "instance_state_unknown",
    );
  });
});

describe("T-WF-001 / T-WF-002 M3 workflow definition compatibility", () => {
  it("M3-WF-AC-001 accepts dotted definition keys but keeps graph keys simple", () => {
    const dotted = makeDefinitionInput();
    dotted.key = "retail.inventory.standard";
    expect(defineVersionedWorkflow(dotted).key).toBe(
      "retail.inventory.standard",
    );

    const dottedState = makeDefinitionInput();
    dottedState.states[0]!.key = "inventory.draft";
    dottedState.initialStateKey = "inventory.draft";
    expectPolicyError(
      () => defineVersionedWorkflow(dottedState),
      "invalid_definition",
    );

    const tooLong = makeDefinitionInput();
    tooLong.key = `a.${"b".repeat(64)}.${"c".repeat(64)}`;
    expectPolicyError(
      () => defineVersionedWorkflow(tooLong),
      "invalid_definition_key",
    );
  });

  it("M3-WF-AC-002 accepts only trusted lead/deal guards and inert effects", () => {
    const definition = makeDefinitionInput();
    definition.transitions[0]!.guardKey = "lender_approval_recorded";
    definition.transitions[0]!.effectKeys = [
      "deal.document_readiness_review",
      "deal.inventory_release_review",
    ];

    expect(defineVersionedWorkflow(definition).transitions[0]).toMatchObject({
      guardKey: "lender_approval_recorded",
      effectKeys: [
        "deal.document_readiness_review",
        "deal.inventory_release_review",
      ],
    });
  });

  it("M3-WF-AC-003 aligns the transition reason limit with SQL at 2,000 characters", () => {
    const definition = defineVersionedWorkflow(makeDefinitionInput());
    const instance: WorkflowInstanceSnapshot = {
      ...INSTANCE,
      currentStateKey: "ready",
      canonicalCategory: "active",
      version: 4,
    };
    const command = {
      definition,
      instance,
      transitionKey: "complete_sale",
      expectedVersion: 4,
      effectivePermissionKeys: ["inventory.transition"],
      fields: {},
      guardResults: { sale_completion_requirements_met: true },
      eventId: "workflow-event-reason-limit",
      actorId: "user-001",
      correlationId: "correlation-reason-limit",
      occurredAt: "2026-07-16T15:00:00Z",
    } as const;

    expect(
      executeWorkflowTransition({ ...command, reason: "a".repeat(2_000) })
        .workflowEvent.reason,
    ).toHaveLength(2_000);
    expectPolicyError(
      () =>
        executeWorkflowTransition({
          ...command,
          reason: "a".repeat(2_001),
        }),
      "invalid_reason",
    );
  });

  it("M3-WF-AC-004 snapshots decision inputs and inert effects without entity values", () => {
    const result = executeWorkflowTransition({
      definition: defineVersionedWorkflow(makeDefinitionInput()),
      instance: INSTANCE,
      transitionKey: "mark_ready",
      expectedVersion: 3,
      effectivePermissionKeys: ["inventory.transition"],
      fields: {
        vin: "1HGCM82633A004352",
        location_id: "location-001",
        customer_private_note: "must never be copied into workflow events",
      },
      guardResults: { required_fields_complete: true },
      eventId: "workflow-event-snapshot",
      actorId: "user-001",
      correlationId: "correlation-snapshot",
      occurredAt: "2026-07-16T15:00:00Z",
    });

    expect(result.workflowEvent.inputSnapshot).toEqual({
      requiredFieldKeys: ["vin", "location_id"],
      guardKey: "required_fields_complete",
      guardSatisfied: true,
      reasonProvided: false,
    });
    expect(result.workflowEvent.effectSnapshot).toEqual({
      effectKeys: ["listing.publish", "listing.refresh"],
    });
    expect(JSON.stringify(result.workflowEvent)).not.toContain(
      "customer_private_note",
    );
    expect(JSON.stringify(result.workflowEvent)).not.toContain(
      "must never be copied",
    );
  });
});
