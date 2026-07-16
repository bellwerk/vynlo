export const WORKFLOW_CANONICAL_CATEGORIES = [
  "draft",
  "active",
  "pending",
  "closed",
  "archived",
] as const;

export type WorkflowCanonicalCategory =
  (typeof WORKFLOW_CANONICAL_CATEGORIES)[number];

/** Milestone 2 guard identifiers implemented by trusted application services. */
export const WORKFLOW_GUARD_KEYS = [
  "required_fields_complete",
  "sale_completion_requirements_met",
] as const;

export type WorkflowGuardKey = (typeof WORKFLOW_GUARD_KEYS)[number];

/** Milestone 2 effects are inert outbox declarations, never direct calls. */
export const WORKFLOW_EFFECT_KEYS = [
  "listing.publish",
  "listing.unpublish",
  "listing.refresh",
  "media.retention_review",
] as const;

export type WorkflowEffectKey = (typeof WORKFLOW_EFFECT_KEYS)[number];

const DEFINITION_KEY_PATTERN = /^[a-z][a-z0-9_]{0,127}$/u;
const FIELD_KEY_PATTERN = /^[a-z][a-z0-9_.-]{0,127}$/u;
const PERMISSION_KEY_PATTERN =
  /^[a-z][a-z0-9_]{0,63}(?:\.[a-z][a-z0-9_]{0,63})+$/u;
const SEMANTIC_VERSION_PATTERN =
  /^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$/u;
const SHA256_PATTERN = /^[0-9a-f]{64}$/u;
const RFC3339_INSTANT_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/u;
const MAX_REASON_LENGTH = 1_000;

const PROHIBITED_EXECUTION_KEYS = new Set([
  "command",
  "endpoint",
  "eval",
  "fetch",
  "filesystem",
  "function",
  "http",
  "https",
  "import",
  "javascript",
  "js",
  "module",
  "network",
  "query",
  "request",
  "script",
  "shell",
  "sql",
  "uri",
  "url",
]);

const PROHIBITED_FIELD_SEGMENTS = new Set([
  "__proto__",
  "constructor",
  "prototype",
]);

export type WorkflowPolicyErrorCode =
  | "invalid_definition"
  | "invalid_definition_key"
  | "invalid_entity_type"
  | "invalid_semantic_version"
  | "invalid_definition_checksum"
  | "duplicate_state_key"
  | "initial_state_missing"
  | "duplicate_transition_key"
  | "transition_state_missing"
  | "terminal_state_has_transition"
  | "invalid_permission_key"
  | "unsupported_guard_key"
  | "unsupported_effect_key"
  | "arbitrary_execution_not_allowed"
  | "invalid_instance"
  | "instance_definition_mismatch"
  | "instance_state_unknown"
  | "transition_not_found"
  | "transition_source_mismatch"
  | "invalid_expected_version"
  | "expected_version_conflict"
  | "permission_denied"
  | "reason_required"
  | "invalid_reason"
  | "required_field_missing"
  | "guard_rejected"
  | "invalid_transition_metadata";

export class WorkflowPolicyError extends Error {
  readonly code: WorkflowPolicyErrorCode;
  readonly detail: string | null;

  constructor(code: WorkflowPolicyErrorCode, detail: string | null = null) {
    super(detail === null ? code : `${code}:${detail}`);
    this.name = "WorkflowPolicyError";
    this.code = code;
    this.detail = detail;
  }
}

export interface WorkflowStateDefinition {
  readonly key: string;
  readonly category: WorkflowCanonicalCategory;
  readonly labels: Readonly<Record<string, string>>;
  readonly flags: Readonly<Record<string, boolean>>;
  readonly requiredFields: readonly string[];
}

export interface WorkflowTransitionDefinition {
  readonly key: string;
  readonly fromStateKey: string;
  readonly toStateKey: string;
  readonly permissionKey: string;
  readonly guardKey: WorkflowGuardKey | null;
  readonly reasonRequired: boolean;
  readonly requiredFields: readonly string[];
  readonly effectKeys: readonly WorkflowEffectKey[];
}

export interface VersionedWorkflowDefinition {
  readonly key: string;
  readonly entityType: string;
  readonly version: string;
  readonly checksum: string;
  readonly initialStateKey: string;
  readonly states: readonly WorkflowStateDefinition[];
  readonly transitions: readonly WorkflowTransitionDefinition[];
}

export interface WorkflowInstanceSnapshot {
  readonly id: string;
  readonly entityId: string;
  readonly definitionKey: string;
  readonly definitionVersion: string;
  readonly definitionChecksum: string;
  readonly currentStateKey: string;
  readonly canonicalCategory: WorkflowCanonicalCategory;
  readonly version: number;
}

export interface WorkflowTransitionEvent {
  readonly id: string;
  readonly instanceId: string;
  readonly entityType: string;
  readonly entityId: string;
  readonly definitionKey: string;
  readonly definitionVersion: string;
  readonly definitionChecksum: string;
  readonly transitionKey: string;
  readonly fromStateKey: string;
  readonly fromCategory: WorkflowCanonicalCategory;
  readonly toStateKey: string;
  readonly toCategory: WorkflowCanonicalCategory;
  readonly actorId: string;
  readonly reason: string | null;
  readonly previousVersion: number;
  readonly resultingVersion: number;
  readonly correlationId: string;
  readonly occurredAt: string;
}

export interface WorkflowOutboxEvent {
  readonly idempotencyKey: string;
  readonly eventType: string;
  readonly aggregateType: string;
  readonly aggregateId: string;
  readonly aggregateVersion: number;
  readonly workflowEventId: string;
  readonly transitionKey: string;
  readonly fromStateKey: string;
  readonly toStateKey: string;
  readonly canonicalCategory: WorkflowCanonicalCategory;
  readonly effectKeys: readonly WorkflowEffectKey[];
  readonly correlationId: string;
  readonly occurredAt: string;
}

export interface WorkflowTransitionResult {
  readonly instance: Readonly<WorkflowInstanceSnapshot>;
  readonly workflowEvent: Readonly<WorkflowTransitionEvent>;
  readonly outboxEvent: Readonly<WorkflowOutboxEvent>;
}

type PlainRecord = Record<string, unknown>;

function requirePlainRecord(
  value: unknown,
  code: WorkflowPolicyErrorCode,
): PlainRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new WorkflowPolicyError(code);
  }
  const prototype = Object.getPrototypeOf(value) as unknown;
  if (prototype !== Object.prototype && prototype !== null) {
    throw new WorkflowPolicyError(code);
  }
  for (const key of Reflect.ownKeys(value)) {
    if (typeof key !== "string") {
      throw new WorkflowPolicyError(code);
    }
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (descriptor?.get || descriptor?.set) {
      throw new WorkflowPolicyError("arbitrary_execution_not_allowed", key);
    }
  }
  return value as PlainRecord;
}

function normalizedExecutionKey(value: string): string {
  return value.toLowerCase().replaceAll(/[^a-z0-9]/gu, "");
}

function assertExactKeys(
  record: PlainRecord,
  allowed: ReadonlySet<string>,
  code: WorkflowPolicyErrorCode,
): void {
  for (const key of Object.keys(record)) {
    if (allowed.has(key)) {
      continue;
    }
    if (PROHIBITED_EXECUTION_KEYS.has(normalizedExecutionKey(key))) {
      throw new WorkflowPolicyError("arbitrary_execution_not_allowed", key);
    }
    throw new WorkflowPolicyError(code, key);
  }
}

function requireDefinitionKey(
  value: unknown,
  code: WorkflowPolicyErrorCode,
): string {
  if (typeof value !== "string" || !DEFINITION_KEY_PATTERN.test(value)) {
    throw new WorkflowPolicyError(code);
  }
  return value;
}

function requireFieldKey(value: unknown): string {
  if (typeof value !== "string" || !FIELD_KEY_PATTERN.test(value)) {
    throw new WorkflowPolicyError("invalid_definition");
  }
  if (value.split(".").some((part) => PROHIBITED_FIELD_SEGMENTS.has(part))) {
    throw new WorkflowPolicyError("invalid_definition");
  }
  return value;
}

function normalizeUniqueFields(value: unknown): readonly string[] {
  if (!Array.isArray(value)) {
    throw new WorkflowPolicyError("invalid_definition");
  }
  const fields = value.map(requireFieldKey);
  if (new Set(fields).size !== fields.length) {
    throw new WorkflowPolicyError("invalid_definition");
  }
  return Object.freeze(fields);
}

function normalizeLabels(value: unknown): Readonly<Record<string, string>> {
  const record = requirePlainRecord(value, "invalid_definition");
  const labels = Object.create(null) as Record<string, string>;
  for (const [locale, label] of Object.entries(record)) {
    if (
      !locale.trim() ||
      typeof label !== "string" ||
      !label.trim() ||
      label.length > 200
    ) {
      throw new WorkflowPolicyError("invalid_definition");
    }
    labels[locale] = label.trim();
  }
  if (Object.keys(labels).length === 0) {
    throw new WorkflowPolicyError("invalid_definition");
  }
  return Object.freeze(labels);
}

function normalizeFlags(value: unknown): Readonly<Record<string, boolean>> {
  const record = requirePlainRecord(value, "invalid_definition");
  const flags = Object.create(null) as Record<string, boolean>;
  for (const [key, enabled] of Object.entries(record)) {
    requireDefinitionKey(key, "invalid_definition");
    if (typeof enabled !== "boolean") {
      throw new WorkflowPolicyError("invalid_definition");
    }
    flags[key] = enabled;
  }
  return Object.freeze(flags);
}

function normalizeState(value: unknown): WorkflowStateDefinition {
  const record = requirePlainRecord(value, "invalid_definition");
  assertExactKeys(
    record,
    new Set(["key", "category", "labels", "flags", "requiredFields"]),
    "invalid_definition",
  );
  if (
    typeof record.category !== "string" ||
    !WORKFLOW_CANONICAL_CATEGORIES.includes(
      record.category as WorkflowCanonicalCategory,
    )
  ) {
    throw new WorkflowPolicyError("invalid_definition");
  }
  return Object.freeze({
    key: requireDefinitionKey(record.key, "invalid_definition"),
    category: record.category as WorkflowCanonicalCategory,
    labels: normalizeLabels(record.labels),
    flags: normalizeFlags(record.flags),
    requiredFields: normalizeUniqueFields(record.requiredFields ?? []),
  });
}

function normalizeGuardKey(value: unknown): WorkflowGuardKey | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (
    typeof value !== "string" ||
    !WORKFLOW_GUARD_KEYS.includes(value as WorkflowGuardKey)
  ) {
    throw new WorkflowPolicyError("unsupported_guard_key");
  }
  return value as WorkflowGuardKey;
}

function normalizeEffectKeys(value: unknown): readonly WorkflowEffectKey[] {
  if (!Array.isArray(value)) {
    throw new WorkflowPolicyError("unsupported_effect_key");
  }
  const effects = value.map((effect) => {
    if (
      typeof effect !== "string" ||
      !WORKFLOW_EFFECT_KEYS.includes(effect as WorkflowEffectKey)
    ) {
      throw new WorkflowPolicyError("unsupported_effect_key");
    }
    return effect as WorkflowEffectKey;
  });
  if (new Set(effects).size !== effects.length) {
    throw new WorkflowPolicyError("invalid_definition");
  }
  return Object.freeze(effects);
}

function normalizeTransition(value: unknown): WorkflowTransitionDefinition {
  const record = requirePlainRecord(value, "invalid_definition");
  assertExactKeys(
    record,
    new Set([
      "key",
      "fromStateKey",
      "toStateKey",
      "permissionKey",
      "guardKey",
      "reasonRequired",
      "requiredFields",
      "effectKeys",
    ]),
    "invalid_definition",
  );
  if (
    typeof record.permissionKey !== "string" ||
    !PERMISSION_KEY_PATTERN.test(record.permissionKey)
  ) {
    throw new WorkflowPolicyError("invalid_permission_key");
  }
  if (typeof record.reasonRequired !== "boolean") {
    throw new WorkflowPolicyError("invalid_definition");
  }
  return Object.freeze({
    key: requireDefinitionKey(record.key, "invalid_definition"),
    fromStateKey: requireDefinitionKey(
      record.fromStateKey,
      "invalid_definition",
    ),
    toStateKey: requireDefinitionKey(record.toStateKey, "invalid_definition"),
    permissionKey: record.permissionKey,
    guardKey: normalizeGuardKey(record.guardKey),
    reasonRequired: record.reasonRequired,
    requiredFields: normalizeUniqueFields(record.requiredFields ?? []),
    effectKeys: normalizeEffectKeys(record.effectKeys ?? []),
  });
}

/**
 * Validates, copies, and deeply freezes a workflow artifact. A change to any
 * definition, state, transition, guard, or effect requires a new version and
 * checksum; instances retain their exact pinned version/checksum.
 */
export function defineVersionedWorkflow(
  value: unknown,
): Readonly<VersionedWorkflowDefinition> {
  const record = requirePlainRecord(value, "invalid_definition");
  assertExactKeys(
    record,
    new Set([
      "key",
      "entityType",
      "version",
      "checksum",
      "initialStateKey",
      "states",
      "transitions",
    ]),
    "invalid_definition",
  );
  const key = requireDefinitionKey(record.key, "invalid_definition_key");
  const entityType = requireDefinitionKey(
    record.entityType,
    "invalid_entity_type",
  );
  if (
    typeof record.version !== "string" ||
    !SEMANTIC_VERSION_PATTERN.test(record.version)
  ) {
    throw new WorkflowPolicyError("invalid_semantic_version");
  }
  if (
    typeof record.checksum !== "string" ||
    !SHA256_PATTERN.test(record.checksum)
  ) {
    throw new WorkflowPolicyError("invalid_definition_checksum");
  }
  if (!Array.isArray(record.states) || record.states.length === 0) {
    throw new WorkflowPolicyError("invalid_definition");
  }
  if (!Array.isArray(record.transitions)) {
    throw new WorkflowPolicyError("invalid_definition");
  }

  const states = record.states.map(normalizeState);
  const transitions = record.transitions.map(normalizeTransition);
  const stateByKey = new Map<string, WorkflowStateDefinition>();
  for (const state of states) {
    if (stateByKey.has(state.key)) {
      throw new WorkflowPolicyError("duplicate_state_key", state.key);
    }
    stateByKey.set(state.key, state);
  }
  const initialStateKey = requireDefinitionKey(
    record.initialStateKey,
    "initial_state_missing",
  );
  if (!stateByKey.has(initialStateKey)) {
    throw new WorkflowPolicyError("initial_state_missing");
  }

  const transitionKeys = new Set<string>();
  for (const transition of transitions) {
    if (transitionKeys.has(transition.key)) {
      throw new WorkflowPolicyError("duplicate_transition_key", transition.key);
    }
    transitionKeys.add(transition.key);
    const fromState = stateByKey.get(transition.fromStateKey);
    if (!fromState || !stateByKey.has(transition.toStateKey)) {
      throw new WorkflowPolicyError("transition_state_missing", transition.key);
    }
    if (transition.fromStateKey === transition.toStateKey) {
      throw new WorkflowPolicyError("invalid_definition", transition.key);
    }
    if (
      fromState.flags.terminal === true ||
      fromState.category === "closed" ||
      fromState.category === "archived"
    ) {
      throw new WorkflowPolicyError(
        "terminal_state_has_transition",
        transition.key,
      );
    }
  }

  return Object.freeze({
    key,
    entityType,
    version: record.version,
    checksum: record.checksum,
    initialStateKey,
    states: Object.freeze(states),
    transitions: Object.freeze(transitions),
  });
}

function hasOwn(record: object, key: PropertyKey): boolean {
  return Object.prototype.hasOwnProperty.call(record, key);
}

function isPresent(value: unknown): boolean {
  return (
    value !== null &&
    value !== undefined &&
    typeof value !== "function" &&
    typeof value !== "symbol" &&
    (typeof value !== "string" || value.trim().length > 0)
  );
}

function requireOpaqueIdentifier(
  value: unknown,
  code: WorkflowPolicyErrorCode = "invalid_transition_metadata",
): string {
  if (typeof value !== "string" || !value.trim() || value.length > 200) {
    throw new WorkflowPolicyError(code);
  }
  return value.trim();
}

function requireInstanceVersion(value: unknown): number {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < 1 ||
    (value as number) >= Number.MAX_SAFE_INTEGER
  ) {
    throw new WorkflowPolicyError("invalid_expected_version");
  }
  return value as number;
}

function normalizeInstant(value: unknown): string {
  if (typeof value !== "string" || !RFC3339_INSTANT_PATTERN.test(value)) {
    throw new WorkflowPolicyError("invalid_transition_metadata");
  }
  const instant = Date.parse(value);
  if (!Number.isFinite(instant)) {
    throw new WorkflowPolicyError("invalid_transition_metadata");
  }
  return new Date(instant).toISOString();
}

function normalizeReason(value: unknown, required: boolean): string | null {
  if (value === null || value === undefined) {
    if (required) {
      throw new WorkflowPolicyError("reason_required");
    }
    return null;
  }
  if (typeof value !== "string") {
    throw new WorkflowPolicyError("invalid_reason");
  }
  const reason = value.trim();
  if (!reason) {
    if (required) {
      throw new WorkflowPolicyError("reason_required");
    }
    return null;
  }
  if (reason.length > MAX_REASON_LENGTH) {
    throw new WorkflowPolicyError("invalid_reason");
  }
  return reason;
}

/**
 * Produces a deterministic transition plan. The caller supplies authoritative
 * guard results and event metadata; this function has no clock, randomness,
 * persistence, provider, filesystem, or network side effects.
 */
export function executeWorkflowTransition(input: {
  readonly definition: VersionedWorkflowDefinition;
  readonly instance: WorkflowInstanceSnapshot;
  readonly transitionKey: string;
  readonly expectedVersion: number;
  readonly effectivePermissionKeys: readonly string[];
  readonly fields: Readonly<Record<string, unknown>>;
  readonly guardResults?: Readonly<Partial<Record<WorkflowGuardKey, boolean>>>;
  readonly reason?: string | null;
  readonly eventId: string;
  readonly actorId: string;
  readonly correlationId: string;
  readonly occurredAt: string;
}): Readonly<WorkflowTransitionResult> {
  const definition = defineVersionedWorkflow(input.definition);
  const fields = requirePlainRecord(
    input.fields,
    "invalid_transition_metadata",
  );
  if (
    !Array.isArray(input.effectivePermissionKeys) ||
    input.effectivePermissionKeys.some(
      (permissionKey) =>
        typeof permissionKey !== "string" ||
        !PERMISSION_KEY_PATTERN.test(permissionKey),
    )
  ) {
    throw new WorkflowPolicyError("permission_denied");
  }
  const expectedVersion = requireInstanceVersion(input.expectedVersion);
  const instanceVersion = requireInstanceVersion(input.instance.version);
  const instanceId = requireOpaqueIdentifier(
    input.instance.id,
    "invalid_instance",
  );
  const entityId = requireOpaqueIdentifier(
    input.instance.entityId,
    "invalid_instance",
  );
  if (
    input.instance.definitionKey !== definition.key ||
    input.instance.definitionVersion !== definition.version ||
    input.instance.definitionChecksum !== definition.checksum
  ) {
    throw new WorkflowPolicyError("instance_definition_mismatch");
  }
  const currentState = definition.states.find(
    (state) => state.key === input.instance.currentStateKey,
  );
  if (
    !currentState ||
    currentState.category !== input.instance.canonicalCategory
  ) {
    throw new WorkflowPolicyError("instance_state_unknown");
  }
  if (instanceVersion !== expectedVersion) {
    throw new WorkflowPolicyError("expected_version_conflict");
  }

  const transition = definition.transitions.find(
    (candidate) => candidate.key === input.transitionKey,
  );
  if (!transition) {
    throw new WorkflowPolicyError("transition_not_found");
  }
  if (transition.fromStateKey !== input.instance.currentStateKey) {
    throw new WorkflowPolicyError("transition_source_mismatch");
  }
  if (!input.effectivePermissionKeys.includes(transition.permissionKey)) {
    throw new WorkflowPolicyError(
      "permission_denied",
      transition.permissionKey,
    );
  }
  const reason = normalizeReason(input.reason, transition.reasonRequired);
  const targetState = definition.states.find(
    (state) => state.key === transition.toStateKey,
  );
  if (!targetState) {
    throw new WorkflowPolicyError("transition_state_missing");
  }
  const requiredFields = [
    ...transition.requiredFields,
    ...targetState.requiredFields,
  ];
  for (const field of new Set(requiredFields)) {
    if (!hasOwn(fields, field) || !isPresent(fields[field])) {
      throw new WorkflowPolicyError("required_field_missing", field);
    }
  }
  if (transition.guardKey !== null) {
    const guardResults = requirePlainRecord(
      input.guardResults ?? {},
      "guard_rejected",
    );
    assertExactKeys(
      guardResults,
      new Set<string>(WORKFLOW_GUARD_KEYS),
      "guard_rejected",
    );
    if (
      Object.values(guardResults).some((result) => typeof result !== "boolean")
    ) {
      throw new WorkflowPolicyError("guard_rejected", transition.guardKey);
    }
    if (guardResults[transition.guardKey] !== true) {
      throw new WorkflowPolicyError("guard_rejected", transition.guardKey);
    }
  }

  const eventId = requireOpaqueIdentifier(input.eventId);
  const actorId = requireOpaqueIdentifier(input.actorId);
  const correlationId = requireOpaqueIdentifier(input.correlationId);
  const occurredAt = normalizeInstant(input.occurredAt);
  const resultingVersion = instanceVersion + 1;
  const nextInstance = Object.freeze({
    ...input.instance,
    id: instanceId,
    entityId,
    currentStateKey: transition.toStateKey,
    canonicalCategory: targetState.category,
    version: resultingVersion,
  });
  const workflowEvent = Object.freeze({
    id: eventId,
    instanceId,
    entityType: definition.entityType,
    entityId,
    definitionKey: definition.key,
    definitionVersion: definition.version,
    definitionChecksum: definition.checksum,
    transitionKey: transition.key,
    fromStateKey: transition.fromStateKey,
    fromCategory: currentState.category,
    toStateKey: transition.toStateKey,
    toCategory: targetState.category,
    actorId,
    reason,
    previousVersion: instanceVersion,
    resultingVersion,
    correlationId,
    occurredAt,
  });
  const effectKeys = Object.freeze([...transition.effectKeys]);
  const outboxEvent = Object.freeze({
    idempotencyKey: `${eventId}:transitioned`,
    eventType: `${definition.entityType}.transitioned`,
    aggregateType: definition.entityType,
    aggregateId: entityId,
    aggregateVersion: resultingVersion,
    workflowEventId: eventId,
    transitionKey: transition.key,
    fromStateKey: transition.fromStateKey,
    toStateKey: transition.toStateKey,
    canonicalCategory: targetState.category,
    effectKeys,
    correlationId,
    occurredAt,
  });

  return Object.freeze({
    instance: nextInstance,
    workflowEvent,
    outboxEvent,
  });
}
