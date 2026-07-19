import { createHash } from "node:crypto";

import DecimalJs from "decimal.js";

export const CALCULATION_ENGINE_VERSION = "vynlo-calculation-v1" as const;

export const Decimal = DecimalJs.clone({
  precision: 80,
  rounding: DecimalJs.ROUND_HALF_UP,
  maxE: 1_000_000,
  minE: -1_000_000,
  modulo: DecimalJs.ROUND_DOWN,
  crypto: false,
});

export type CalculationStatus =
  "draft" | "validated" | "test_passed" | "approved" | "active" | "retired";

export type CalculationJson =
  | null
  | boolean
  | string
  | number
  | readonly CalculationJson[]
  | { readonly [key: string]: CalculationJson };

export type RoundingMode = "half_up" | "half_even" | "down" | "up";

export type RowPredicate =
  | Readonly<{ all: readonly RowPredicate[] }>
  | Readonly<{ any: readonly RowPredicate[] }>
  | Readonly<{ not: RowPredicate }>
  | Readonly<{
      path: string;
      eq?: CalculationJson;
      ne?: CalculationJson;
      lt?: CalculationJson;
      lte?: CalculationJson;
      gt?: CalculationJson;
      gte?: CalculationJson;
    }>;

export type CalculationExpression =
  | Readonly<{ op: "constant"; value: CalculationJson }>
  | Readonly<{ op: "field"; path: string }>
  | Readonly<{ op: "output"; key: string }>
  | Readonly<{
      op: "add" | "sum" | "subtract" | "multiply" | "divide" | "min" | "max";
      args: readonly CalculationExpression[];
    }>
  | Readonly<{
      op: "percentage";
      value: CalculationExpression;
      percentage: CalculationExpression;
    }>
  | Readonly<{ op: "abs"; value: CalculationExpression }>
  | Readonly<{
      op: "round";
      value: CalculationExpression;
      scale: number;
      mode: RoundingMode;
    }>
  | Readonly<{
      op: "floor" | "ceil";
      value: CalculationExpression;
      scale?: number;
    }>
  | Readonly<{
      op: "eq" | "ne" | "lt" | "lte" | "gt" | "gte";
      left: CalculationExpression;
      right: CalculationExpression;
    }>
  | Readonly<{
      op: "if";
      condition: CalculationExpression;
      then: CalculationExpression;
      else: CalculationExpression;
    }>
  | Readonly<{ op: "coalesce"; args: readonly CalculationExpression[] }>
  | Readonly<{
      op: "sum_rows";
      rows_path: string;
      value_path: string;
      where?: RowPredicate | null;
    }>
  | Readonly<{
      op: "date_add_days";
      date: CalculationExpression;
      days: CalculationExpression;
    }>
  | Readonly<{
      op: "date_difference_days";
      start: CalculationExpression;
      end: CalculationExpression;
    }>
  | Readonly<{
      op: "tax_pack";
      context: string;
      inputs: Readonly<Record<string, CalculationExpression>>;
      output: string;
    }>
  | Readonly<{
      op: "amortized_payment";
      principal_minor: CalculationExpression;
      annual_rate_bps: CalculationExpression;
      periods_per_year: CalculationExpression;
      number_of_periods: CalculationExpression;
      rounding: Readonly<{ mode: RoundingMode; minor_unit: number }>;
    }>;

export interface CalculationDefinition {
  readonly key: string;
  readonly version: string;
  readonly status: CalculationStatus;
  readonly input_schema: Readonly<Record<string, unknown>>;
  readonly outputs: Readonly<Record<string, CalculationExpression>>;
  readonly rounding: Readonly<Record<string, CalculationJson>>;
  readonly fixtures: readonly string[];
  readonly approval_refs?: readonly string[];
  readonly metadata?: Readonly<Record<string, CalculationJson>>;
}

export interface CalculationLimits {
  readonly maximumDepth: number;
  readonly maximumInputBytes: number;
  readonly maximumNodes: number;
  readonly maximumOutputBytes: number;
  readonly maximumOutputs: number;
  readonly maximumRows: number;
  readonly maximumRuntimeMs: number;
}

export const DEFAULT_CALCULATION_LIMITS: Readonly<CalculationLimits> =
  Object.freeze({
    maximumDepth: 64,
    maximumInputBytes: 256 * 1024,
    maximumNodes: 10_000,
    maximumOutputBytes: 256 * 1024,
    maximumOutputs: 128,
    maximumRows: 10_000,
    maximumRuntimeMs: 250,
  });

export type CalculationErrorCode =
  | "division_by_zero"
  | "forbidden_path"
  | "invalid_arity"
  | "invalid_date"
  | "invalid_definition"
  | "invalid_expression"
  | "invalid_input"
  | "invalid_path"
  | "missing_field"
  | "missing_output"
  | "numeric_overflow"
  | "output_cycle"
  | "resource_limit_exceeded"
  | "tax_invocation_failed"
  | "type_mismatch"
  | "unknown_operation";

export class CalculationRuntimeError extends Error {
  readonly code: CalculationErrorCode;
  readonly location: string;

  constructor(code: CalculationErrorCode, location = "definition") {
    super(`Calculation failed safely: ${code}.`);
    this.name = "CalculationRuntimeError";
    this.code = code;
    this.location = location;
  }
}

export interface TaxInvocationRequest {
  readonly context: string;
  readonly inputs: Readonly<Record<string, CalculationJson>>;
}

export interface TaxInvocationResult {
  readonly outputs: Readonly<Record<string, CalculationJson>>;
  readonly packKey: string;
  readonly packVersion: string;
  readonly packChecksum: string;
  readonly snapshotChecksum: string;
}

export interface CalculationTaxPort {
  calculate(request: TaxInvocationRequest): TaxInvocationResult;
}

export interface CompiledCalculationDefinition {
  readonly checksum: string;
  readonly definition: Readonly<CalculationDefinition>;
  readonly limits: Readonly<CalculationLimits>;
  readonly outputOrder: readonly string[];
}

export interface CalculationTaxComponent {
  readonly context: string;
  readonly output: string;
  readonly packKey: string;
  readonly packVersion: string;
  readonly packChecksum: string;
  readonly snapshotChecksum: string;
}

export interface CalculationSnapshot {
  readonly definitionKey: string;
  readonly definitionVersion: string;
  readonly definitionChecksum: string;
  readonly definition: CalculationJson;
  readonly engineVersion: string;
  readonly input: CalculationJson;
  readonly output: Readonly<Record<string, CalculationJson>>;
  readonly components: readonly Readonly<{
    key: string;
    value: CalculationJson;
  }>[];
  readonly taxComponents: readonly CalculationTaxComponent[];
  readonly rounding: CalculationJson;
  readonly checksum: string;
}

const KEY_PATTERN = /^[a-z0-9][a-z0-9-_]{1,127}$/u;
const OUTPUT_KEY_PATTERN = /^[a-z][a-z0-9_]{0,127}$/u;
const SEMVER_PATTERN = /^\d+\.\d+\.\d+$/u;
const DECIMAL_PATTERN = /^-?(?:0|[1-9]\d*)(?:\.\d+)?$/u;
const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/u;
const FORBIDDEN_PATH_SEGMENTS = new Set([
  "__proto__",
  "prototype",
  "constructor",
]);

function isSafeOutputKey(value: unknown): value is string {
  return (
    typeof value === "string" &&
    OUTPUT_KEY_PATTERN.test(value) &&
    !FORBIDDEN_PATH_SEGMENTS.has(value)
  );
}

interface InternalRecord {
  readonly [key: string]: InternalValue;
}

type InternalArray = ReadonlyArray<InternalValue>;

type InternalValue =
  | null
  | boolean
  | string
  | InstanceType<typeof Decimal>
  | InternalArray
  | InternalRecord;

type MutableJsonRecord = Record<string, CalculationJson>;

interface JsonValidationState {
  readonly seen: WeakSet<object>;
  nodes: number;
}

const MAXIMUM_JSON_DEPTH = 128;
const MAXIMUM_JSON_NODES = 100_000;

function isInternalArray(value: InternalValue): value is InternalArray {
  return Array.isArray(value);
}

function isInternalRecord(value: InternalValue): value is InternalRecord {
  return (
    value !== null &&
    typeof value === "object" &&
    !(value instanceof Decimal) &&
    !Array.isArray(value)
  );
}

function fail(code: CalculationErrorCode, location?: string): never {
  throw new CalculationRuntimeError(code, location);
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function assertExactKeys(
  value: Record<string, unknown>,
  required: readonly string[],
  optional: readonly string[],
  location: string,
): void {
  const allowed = new Set([...required, ...optional]);
  if (
    required.some((key) => !Object.hasOwn(value, key)) ||
    Object.keys(value).some((key) => !allowed.has(key))
  ) {
    fail("invalid_expression", location);
  }
}

function validatePath(path: unknown, location: string): string[] {
  if (typeof path !== "string" || path.length < 1 || path.length > 256) {
    fail("invalid_path", location);
  }
  const segments = path.split(".");
  if (
    segments.some(
      (segment) => !/^(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9]\d*)$/u.test(segment),
    )
  ) {
    fail("invalid_path", location);
  }
  if (segments.some((segment) => FORBIDDEN_PATH_SEGMENTS.has(segment))) {
    fail("forbidden_path", location);
  }
  return segments;
}

function validateJson(
  value: unknown,
  location: string,
  state: JsonValidationState = { seen: new WeakSet<object>(), nodes: 0 },
  depth = 0,
): CalculationJson {
  state.nodes += 1;
  if (depth > MAXIMUM_JSON_DEPTH || state.nodes > MAXIMUM_JSON_NODES) {
    fail("resource_limit_exceeded", location);
  }
  if (
    value === null ||
    typeof value === "boolean" ||
    typeof value === "string"
  ) {
    return value;
  }
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) fail("invalid_input", location);
    return value;
  }
  if (Array.isArray(value)) {
    if (state.seen.has(value)) fail("invalid_input", location);
    state.seen.add(value);
    const result = value.map((item, index) =>
      validateJson(item, `${location}[${index}]`, state, depth + 1),
    );
    state.seen.delete(value);
    return result;
  }
  if (!isPlainRecord(value)) fail("invalid_input", location);
  if (state.seen.has(value)) fail("invalid_input", location);
  state.seen.add(value);
  const result: MutableJsonRecord = Object.create(null) as MutableJsonRecord;
  for (const key of Object.keys(value).sort()) {
    if (FORBIDDEN_PATH_SEGMENTS.has(key)) fail("forbidden_path", location);
    result[key] = validateJson(
      value[key],
      `${location}.${key}`,
      state,
      depth + 1,
    );
  }
  state.seen.delete(value);
  return result;
}

export function canonicalJson(value: CalculationJson): string {
  if (
    value === null ||
    typeof value === "boolean" ||
    typeof value === "number"
  ) {
    return JSON.stringify(value);
  }
  if (typeof value === "string") return JSON.stringify(value);
  if (isCalculationJsonArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }
  return `{${Object.keys(value)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key]!)}`)
    .join(",")}}`;
}

function isCalculationJsonArray(
  value: CalculationJson,
): value is readonly CalculationJson[] {
  return Array.isArray(value);
}

export function sha256Hex(value: string | Uint8Array): string {
  return createHash("sha256").update(value).digest("hex");
}

function canonicalClone(value: unknown, location: string): CalculationJson {
  return JSON.parse(
    canonicalJson(validateJson(value, location)),
  ) as CalculationJson;
}

function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

function validateLimits(
  input: Partial<CalculationLimits> | undefined,
): CalculationLimits {
  const result = { ...DEFAULT_CALCULATION_LIMITS, ...input };
  for (const [key, value] of Object.entries(result)) {
    if (!Number.isSafeInteger(value) || value < 1) {
      fail("invalid_definition", `limits.${key}`);
    }
  }
  return Object.freeze(result);
}

interface CompileState {
  depth: number;
  readonly counter: { nodes: number };
  readonly limits: CalculationLimits;
  readonly outputDependencies: Map<string, Set<string>>;
  outputKey: string;
}

function enterNode(state: CompileState, location: string): CompileState {
  const nodes = state.counter.nodes + 1;
  const depth = state.depth + 1;
  if (nodes > state.limits.maximumNodes || depth > state.limits.maximumDepth) {
    fail("resource_limit_exceeded", location);
  }
  state.counter.nodes = nodes;
  return { ...state, depth };
}

function validatePredicate(
  value: unknown,
  state: CompileState,
  location: string,
): RowPredicate {
  if (!isPlainRecord(value)) {
    fail("invalid_expression", location);
  }
  const next = enterNode(state, location);
  const keys = Object.keys(value);
  if (keys.length === 1 && ["all", "any"].includes(keys[0]!)) {
    const operator = keys[0] as "all" | "any";
    const children = value[operator];
    if (
      !Array.isArray(children) ||
      children.length < 1 ||
      children.length > 100
    ) {
      fail("invalid_expression", location);
    }
    return {
      [operator]: children.map((child, index) =>
        validatePredicate(child, next, `${location}.${operator}[${index}]`),
      ),
    } as unknown as RowPredicate;
  }
  if (keys.length === 1 && keys[0] === "not") {
    return {
      not: validatePredicate(value.not, next, `${location}.not`),
    };
  }
  if (typeof value.path !== "string") fail("invalid_expression", location);
  validatePath(value.path, `${location}.path`);
  const comparators = ["eq", "ne", "lt", "lte", "gt", "gte"].filter((key) =>
    Object.hasOwn(value, key),
  );
  if (comparators.length !== 1 || keys.length !== 2 || !keys.includes("path")) {
    fail("invalid_expression", location);
  }
  const comparator = comparators[0]!;
  return {
    path: value.path,
    [comparator]: validateJson(value[comparator], `${location}.${comparator}`),
  } as RowPredicate;
}

function validateExpression(
  value: unknown,
  state: CompileState,
  location: string,
): CalculationExpression {
  if (!isPlainRecord(value) || typeof value.op !== "string") {
    fail("invalid_expression", location);
  }
  const next = enterNode(state, location);
  switch (value.op) {
    case "constant": {
      assertExactKeys(value, ["op", "value"], [], location);
      return {
        op: "constant",
        value: validateJson(value.value, `${location}.value`),
      };
    }
    case "field": {
      assertExactKeys(value, ["op", "path"], [], location);
      validatePath(value.path, `${location}.path`);
      return { op: "field", path: value.path as string };
    }
    case "output": {
      assertExactKeys(value, ["op", "key"], [], location);
      if (!isSafeOutputKey(value.key)) {
        if (
          typeof value.key === "string" &&
          FORBIDDEN_PATH_SEGMENTS.has(value.key)
        ) {
          fail("forbidden_path", location);
        }
        fail("invalid_expression", location);
      }
      state.outputDependencies.get(state.outputKey)!.add(value.key);
      return { op: "output", key: value.key };
    }
    case "add":
    case "sum":
    case "subtract":
    case "multiply":
    case "divide":
    case "min":
    case "max": {
      assertExactKeys(value, ["op", "args"], [], location);
      if (!Array.isArray(value.args)) fail("invalid_expression", location);
      const minimum = ["subtract", "divide"].includes(value.op) ? 2 : 1;
      if (value.args.length < minimum || value.args.length > 1_000) {
        fail("invalid_arity", location);
      }
      return {
        op: value.op,
        args: value.args.map((argument, index) =>
          validateExpression(argument, next, `${location}.args[${index}]`),
        ),
      };
    }
    case "percentage": {
      assertExactKeys(value, ["op", "value", "percentage"], [], location);
      return {
        op: "percentage",
        value: validateExpression(value.value, next, `${location}.value`),
        percentage: validateExpression(
          value.percentage,
          next,
          `${location}.percentage`,
        ),
      };
    }
    case "abs": {
      assertExactKeys(value, ["op", "value"], [], location);
      return {
        op: "abs",
        value: validateExpression(value.value, next, `${location}.value`),
      };
    }
    case "round": {
      assertExactKeys(value, ["op", "value", "scale", "mode"], [], location);
      if (
        !Number.isInteger(value.scale) ||
        (value.scale as number) < 0 ||
        (value.scale as number) > 8 ||
        !["half_up", "half_even", "down", "up"].includes(value.mode as string)
      ) {
        fail("invalid_expression", location);
      }
      return {
        op: "round",
        value: validateExpression(value.value, next, `${location}.value`),
        scale: value.scale as number,
        mode: value.mode as RoundingMode,
      };
    }
    case "floor":
    case "ceil": {
      assertExactKeys(value, ["op", "value"], ["scale"], location);
      const scale = value.scale ?? 0;
      if (
        !Number.isInteger(scale) ||
        (scale as number) < 0 ||
        (scale as number) > 8
      ) {
        fail("invalid_expression", location);
      }
      return {
        op: value.op,
        value: validateExpression(value.value, next, `${location}.value`),
        scale: scale as number,
      };
    }
    case "eq":
    case "ne":
    case "lt":
    case "lte":
    case "gt":
    case "gte": {
      assertExactKeys(value, ["op", "left", "right"], [], location);
      return {
        op: value.op,
        left: validateExpression(value.left, next, `${location}.left`),
        right: validateExpression(value.right, next, `${location}.right`),
      };
    }
    case "if": {
      assertExactKeys(value, ["op", "condition", "then", "else"], [], location);
      return {
        op: "if",
        condition: validateExpression(
          value.condition,
          next,
          `${location}.condition`,
        ),
        then: validateExpression(value.then, next, `${location}.then`),
        else: validateExpression(value.else, next, `${location}.else`),
      };
    }
    case "coalesce": {
      assertExactKeys(value, ["op", "args"], [], location);
      if (
        !Array.isArray(value.args) ||
        value.args.length < 1 ||
        value.args.length > 100
      ) {
        fail("invalid_arity", location);
      }
      return {
        op: "coalesce",
        args: value.args.map((argument, index) =>
          validateExpression(argument, next, `${location}.args[${index}]`),
        ),
      };
    }
    case "sum_rows": {
      assertExactKeys(
        value,
        ["op", "rows_path", "value_path"],
        ["where"],
        location,
      );
      validatePath(value.rows_path, `${location}.rows_path`);
      validatePath(value.value_path, `${location}.value_path`);
      return {
        op: "sum_rows",
        rows_path: value.rows_path as string,
        value_path: value.value_path as string,
        ...(value.where === undefined
          ? {}
          : {
              where:
                value.where === null
                  ? null
                  : validatePredicate(value.where, next, `${location}.where`),
            }),
      };
    }
    case "date_add_days": {
      assertExactKeys(value, ["op", "date", "days"], [], location);
      return {
        op: "date_add_days",
        date: validateExpression(value.date, next, `${location}.date`),
        days: validateExpression(value.days, next, `${location}.days`),
      };
    }
    case "date_difference_days": {
      assertExactKeys(value, ["op", "start", "end"], [], location);
      return {
        op: "date_difference_days",
        start: validateExpression(value.start, next, `${location}.start`),
        end: validateExpression(value.end, next, `${location}.end`),
      };
    }
    case "tax_pack": {
      assertExactKeys(
        value,
        ["op", "context", "inputs", "output"],
        [],
        location,
      );
      if (
        !isSafeOutputKey(value.context) ||
        !isSafeOutputKey(value.output) ||
        !isPlainRecord(value.inputs) ||
        Object.keys(value.inputs).length > 100
      ) {
        fail("invalid_expression", location);
      }
      const inputs: Record<string, CalculationExpression> = Object.create(
        null,
      ) as Record<string, CalculationExpression>;
      for (const key of Object.keys(value.inputs).sort()) {
        if (!isSafeOutputKey(key)) {
          if (FORBIDDEN_PATH_SEGMENTS.has(key))
            fail("forbidden_path", location);
          fail("invalid_expression", location);
        }
        inputs[key] = validateExpression(
          value.inputs[key],
          next,
          `${location}.inputs.${key}`,
        );
      }
      return {
        op: "tax_pack",
        context: value.context,
        inputs,
        output: value.output,
      };
    }
    case "amortized_payment": {
      assertExactKeys(
        value,
        [
          "op",
          "principal_minor",
          "annual_rate_bps",
          "periods_per_year",
          "number_of_periods",
          "rounding",
        ],
        [],
        location,
      );
      if (!isPlainRecord(value.rounding)) fail("invalid_expression", location);
      assertExactKeys(
        value.rounding,
        ["mode", "minor_unit"],
        [],
        `${location}.rounding`,
      );
      if (
        !["half_up", "half_even", "down", "up"].includes(
          value.rounding.mode as string,
        ) ||
        !Number.isInteger(value.rounding.minor_unit) ||
        (value.rounding.minor_unit as number) < 0 ||
        (value.rounding.minor_unit as number) > 6
      ) {
        fail("invalid_expression", location);
      }
      return {
        op: "amortized_payment",
        principal_minor: validateExpression(
          value.principal_minor,
          next,
          `${location}.principal_minor`,
        ),
        annual_rate_bps: validateExpression(
          value.annual_rate_bps,
          next,
          `${location}.annual_rate_bps`,
        ),
        periods_per_year: validateExpression(
          value.periods_per_year,
          next,
          `${location}.periods_per_year`,
        ),
        number_of_periods: validateExpression(
          value.number_of_periods,
          next,
          `${location}.number_of_periods`,
        ),
        rounding: {
          mode: value.rounding.mode as RoundingMode,
          minor_unit: value.rounding.minor_unit as number,
        },
      };
    }
    default:
      fail("unknown_operation", location);
  }
}

function topologicalOutputOrder(
  outputs: Readonly<Record<string, CalculationExpression>>,
  dependencies: ReadonlyMap<string, ReadonlySet<string>>,
): readonly string[] {
  const order: string[] = [];
  const visiting = new Set<string>();
  const visited = new Set<string>();
  const visit = (key: string): void => {
    if (!Object.hasOwn(outputs, key)) fail("missing_output", `outputs.${key}`);
    if (visiting.has(key)) fail("output_cycle", `outputs.${key}`);
    if (visited.has(key)) return;
    visiting.add(key);
    for (const dependency of [...(dependencies.get(key) ?? [])].sort()) {
      visit(dependency);
    }
    visiting.delete(key);
    visited.add(key);
    order.push(key);
  };
  for (const key of Object.keys(outputs).sort()) visit(key);
  return Object.freeze(order);
}

export function compileCalculationDefinition(
  value: unknown,
  limitOverrides?: Partial<CalculationLimits>,
): CompiledCalculationDefinition {
  if (!isPlainRecord(value)) fail("invalid_definition");
  assertExactKeys(
    value,
    [
      "key",
      "version",
      "status",
      "input_schema",
      "outputs",
      "rounding",
      "fixtures",
    ],
    ["approval_refs", "metadata"],
    "definition",
  );
  if (
    typeof value.key !== "string" ||
    !KEY_PATTERN.test(value.key) ||
    typeof value.version !== "string" ||
    !SEMVER_PATTERN.test(value.version) ||
    ![
      "draft",
      "validated",
      "test_passed",
      "approved",
      "active",
      "retired",
    ].includes(value.status as string) ||
    !isPlainRecord(value.input_schema) ||
    !isPlainRecord(value.outputs) ||
    !isPlainRecord(value.rounding) ||
    !Array.isArray(value.fixtures) ||
    value.fixtures.some(
      (fixture) => typeof fixture !== "string" || fixture.length < 1,
    ) ||
    (value.approval_refs !== undefined &&
      (!Array.isArray(value.approval_refs) ||
        value.approval_refs.some(
          (item) => typeof item !== "string" || item.length < 1,
        ))) ||
    (value.metadata !== undefined && !isPlainRecord(value.metadata))
  ) {
    fail("invalid_definition");
  }
  const limits = validateLimits(limitOverrides);
  const outputKeys = Object.keys(value.outputs).sort();
  if (outputKeys.length < 1) fail("invalid_definition", "outputs");
  if (outputKeys.length > limits.maximumOutputs) {
    fail("resource_limit_exceeded", "outputs");
  }
  if (outputKeys.some((key) => FORBIDDEN_PATH_SEGMENTS.has(key))) {
    fail("forbidden_path", "outputs");
  }
  if (outputKeys.some((key) => !isSafeOutputKey(key))) {
    fail("invalid_definition", "outputs");
  }
  const outputDependencies = new Map<string, Set<string>>(
    outputKeys.map((key) => [key, new Set<string>()]),
  );
  const state: CompileState = {
    counter: { nodes: 0 },
    depth: 0,
    limits,
    outputDependencies,
    outputKey: outputKeys[0]!,
  };
  const outputs: Record<string, CalculationExpression> = Object.create(
    null,
  ) as Record<string, CalculationExpression>;
  for (const key of outputKeys) {
    state.outputKey = key;
    state.depth = 0;
    outputs[key] = validateExpression(
      value.outputs[key],
      state,
      `outputs.${key}`,
    );
  }
  const definition: CalculationDefinition = {
    key: value.key,
    version: value.version,
    status: value.status as CalculationStatus,
    input_schema: canonicalClone(
      value.input_schema,
      "input_schema",
    ) as Readonly<Record<string, unknown>>,
    outputs,
    rounding: canonicalClone(value.rounding, "rounding") as Readonly<
      Record<string, CalculationJson>
    >,
    fixtures: Object.freeze([...(value.fixtures as string[])]),
    ...(value.approval_refs === undefined
      ? {}
      : {
          approval_refs: Object.freeze([...(value.approval_refs as string[])]),
        }),
    ...(value.metadata === undefined
      ? {}
      : {
          metadata: canonicalClone(value.metadata, "metadata") as Readonly<
            Record<string, CalculationJson>
          >,
        }),
  };
  const artifactContent = {
    key: definition.key,
    version: definition.version,
    input_schema: definition.input_schema,
    outputs: definition.outputs,
    rounding: definition.rounding,
    fixtures: definition.fixtures,
    ...(definition.metadata === undefined
      ? {}
      : { metadata: definition.metadata }),
  };
  const frozenDefinition = deepFreeze(definition);
  return Object.freeze({
    // Lifecycle state and approval links change as the immutable content moves
    // through gates. They are snapshotted, but are not part of the stable
    // content checksum bound by those approvals.
    checksum: sha256Hex(
      canonicalJson(canonicalClone(artifactContent, "artifact_content")),
    ),
    definition: frozenDefinition,
    limits,
    outputOrder: topologicalOutputOrder(outputs, outputDependencies),
  });
}

function toDecimal(
  value: InternalValue,
  location: string,
): InstanceType<typeof Decimal> {
  let decimal: InstanceType<typeof Decimal>;
  try {
    if (value instanceof Decimal) {
      decimal = value;
    } else if (typeof value === "string" && DECIMAL_PATTERN.test(value)) {
      decimal = new Decimal(value);
    } else {
      fail("type_mismatch", location);
    }
  } catch (error) {
    if (error instanceof CalculationRuntimeError) throw error;
    fail("numeric_overflow", location);
  }
  if (!decimal!.isFinite() || decimal!.e > 100 || decimal!.e < -100) {
    fail("numeric_overflow", location);
  }
  return decimal!;
}

function integerDecimal(
  value: InternalValue,
  location: string,
  minimum?: number,
): InstanceType<typeof Decimal> {
  const decimal = toDecimal(value, location);
  if (!decimal.isInteger() || (minimum !== undefined && decimal.lt(minimum))) {
    fail("type_mismatch", location);
  }
  return decimal;
}

function decimalRounding(mode: RoundingMode): DecimalJs.Rounding {
  switch (mode) {
    case "half_up":
      return Decimal.ROUND_HALF_UP;
    case "half_even":
      return Decimal.ROUND_HALF_EVEN;
    case "down":
      return Decimal.ROUND_DOWN;
    case "up":
      return Decimal.ROUND_UP;
  }
}

function internalize(value: CalculationJson): InternalValue {
  if (typeof value === "number") return new Decimal(value.toString());
  if (Array.isArray(value)) return value.map((item) => internalize(item));
  if (value !== null && typeof value === "object") {
    const result: Record<string, InternalValue> = Object.create(null) as Record<
      string,
      InternalValue
    >;
    for (const [key, item] of Object.entries(value))
      result[key] = internalize(item);
    return result;
  }
  return value;
}

function externalize(value: InternalValue): CalculationJson {
  if (value instanceof Decimal) {
    if (!value.isFinite() || Math.abs(value.e) > 100) fail("numeric_overflow");
    return value.toFixed();
  }
  if (isInternalArray(value)) return value.map((item) => externalize(item));
  if (isInternalRecord(value)) {
    const result: MutableJsonRecord = Object.create(null) as MutableJsonRecord;
    for (const key of Object.keys(value).sort())
      result[key] = externalize(value[key]!);
    return result;
  }
  return value;
}

function getPath(
  root: InternalValue,
  path: string,
  location: string,
): InternalValue {
  const segments = validatePath(path, location);
  let current = root;
  for (const segment of segments) {
    if (isInternalArray(current)) {
      const index = Number(segment);
      if (
        !Number.isSafeInteger(index) ||
        index < 0 ||
        index >= current.length
      ) {
        fail("missing_field", location);
      }
      current = current[index]!;
    } else if (isInternalRecord(current) && Object.hasOwn(current, segment)) {
      current = current[segment]!;
    } else {
      fail("missing_field", location);
    }
  }
  return current;
}

function parseDate(value: InternalValue, location: string): number {
  if (typeof value !== "string") fail("type_mismatch", location);
  const match = DATE_PATTERN.exec(value);
  if (!match) fail("invalid_date", location);
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(0);
  date.setUTCHours(0, 0, 0, 0);
  date.setUTCFullYear(year, month - 1, day);
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day ||
    year < 1 ||
    year > 9999
  ) {
    fail("invalid_date", location);
  }
  return date.getTime();
}

function formatDate(milliseconds: number, location: string): string {
  const date = new Date(milliseconds);
  if (
    !Number.isFinite(milliseconds) ||
    date.getUTCFullYear() < 1 ||
    date.getUTCFullYear() > 9999
  ) {
    fail("invalid_date", location);
  }
  return date.toISOString().slice(0, 10);
}

function compareValues(
  left: InternalValue,
  right: InternalValue,
  op: "eq" | "ne" | "lt" | "lte" | "gt" | "gte",
  location: string,
): boolean {
  let comparison: number;
  const numeric =
    left instanceof Decimal ||
    right instanceof Decimal ||
    (typeof left === "string" &&
      DECIMAL_PATTERN.test(left) &&
      typeof right === "string" &&
      DECIMAL_PATTERN.test(right));
  if (numeric) {
    comparison = toDecimal(left, location).cmp(toDecimal(right, location));
  } else if (
    (typeof left === "string" && typeof right === "string") ||
    (typeof left === "boolean" && typeof right === "boolean") ||
    (left === null && right === null)
  ) {
    comparison = left === right ? 0 : String(left) < String(right) ? -1 : 1;
  } else {
    fail("type_mismatch", location);
  }
  switch (op) {
    case "eq":
      return comparison === 0;
    case "ne":
      return comparison !== 0;
    case "lt":
      return comparison < 0;
    case "lte":
      return comparison <= 0;
    case "gt":
      return comparison > 0;
    case "gte":
      return comparison >= 0;
  }
}

interface EvaluationState {
  readonly compiled: CompiledCalculationDefinition;
  readonly input: InternalValue;
  readonly outputs: Map<string, InternalValue>;
  readonly evaluating: Set<string>;
  readonly taxComponents: CalculationTaxComponent[];
  readonly taxPort: CalculationTaxPort | undefined;
  readonly startedAt: number;
  readonly now: () => number;
  rowsVisited: number;
}

function checkDeadline(state: EvaluationState, location: string): void {
  const elapsed = state.now() - state.startedAt;
  if (
    !Number.isFinite(elapsed) ||
    elapsed < 0 ||
    elapsed > state.compiled.limits.maximumRuntimeMs
  ) {
    fail("resource_limit_exceeded", location);
  }
}

function evaluatePredicate(
  predicate: RowPredicate,
  row: InternalValue,
  location: string,
): boolean {
  if ("all" in predicate) {
    return predicate.all.every((child, index) =>
      evaluatePredicate(child, row, `${location}.all[${index}]`),
    );
  }
  if ("any" in predicate) {
    return predicate.any.some((child, index) =>
      evaluatePredicate(child, row, `${location}.any[${index}]`),
    );
  }
  if ("not" in predicate)
    return !evaluatePredicate(predicate.not, row, `${location}.not`);
  const actual = getPath(row, predicate.path, `${location}.path`);
  for (const op of ["eq", "ne", "lt", "lte", "gt", "gte"] as const) {
    if (Object.hasOwn(predicate, op)) {
      return compareValues(
        actual,
        internalize(predicate[op] as CalculationJson),
        op,
        location,
      );
    }
  }
  fail("invalid_expression", location);
}

function evaluateOutput(key: string, state: EvaluationState): InternalValue {
  const cached = state.outputs.get(key);
  if (cached !== undefined || state.outputs.has(key)) return cached!;
  if (state.evaluating.has(key)) fail("output_cycle", `outputs.${key}`);
  const expression = state.compiled.definition.outputs[key];
  if (expression === undefined) fail("missing_output", `outputs.${key}`);
  state.evaluating.add(key);
  const value = evaluateExpression(expression, state, `outputs.${key}`);
  state.evaluating.delete(key);
  state.outputs.set(key, value);
  return value;
}

function evaluateExpression(
  expression: CalculationExpression,
  state: EvaluationState,
  location: string,
): InternalValue {
  checkDeadline(state, location);
  switch (expression.op) {
    case "constant":
      return internalize(expression.value);
    case "field":
      return getPath(state.input, expression.path, location);
    case "output":
      return evaluateOutput(expression.key, state);
    case "add":
    case "sum":
    case "subtract":
    case "multiply":
    case "divide":
    case "min":
    case "max": {
      const decimals = expression.args.map((argument, index) =>
        toDecimal(
          evaluateExpression(argument, state, `${location}.args[${index}]`),
          location,
        ),
      );
      let result = decimals[0]!;
      try {
        for (const current of decimals.slice(1)) {
          if (expression.op === "add" || expression.op === "sum") {
            result = result.add(current);
          } else if (expression.op === "subtract") result = result.sub(current);
          else if (expression.op === "multiply") result = result.mul(current);
          else if (expression.op === "divide") {
            if (current.isZero()) fail("division_by_zero", location);
            result = result.div(current);
          } else if (expression.op === "min")
            result = Decimal.min(result, current);
          else result = Decimal.max(result, current);
        }
      } catch (error) {
        if (error instanceof CalculationRuntimeError) throw error;
        fail("numeric_overflow", location);
      }
      return toDecimal(result, location);
    }
    case "percentage":
      return toDecimal(
        toDecimal(
          evaluateExpression(expression.value, state, `${location}.value`),
          location,
        )
          .mul(
            toDecimal(
              evaluateExpression(
                expression.percentage,
                state,
                `${location}.percentage`,
              ),
              location,
            ),
          )
          .div(100),
        location,
      );
    case "abs":
      return toDecimal(
        evaluateExpression(expression.value, state, `${location}.value`),
        location,
      ).abs();
    case "round":
      return toDecimal(
        evaluateExpression(expression.value, state, `${location}.value`),
        location,
      ).toDecimalPlaces(expression.scale, decimalRounding(expression.mode));
    case "floor":
    case "ceil":
      return toDecimal(
        evaluateExpression(expression.value, state, `${location}.value`),
        location,
      ).toDecimalPlaces(
        expression.scale ?? 0,
        expression.op === "floor" ? Decimal.ROUND_FLOOR : Decimal.ROUND_CEIL,
      );
    case "eq":
    case "ne":
    case "lt":
    case "lte":
    case "gt":
    case "gte":
      return compareValues(
        evaluateExpression(expression.left, state, `${location}.left`),
        evaluateExpression(expression.right, state, `${location}.right`),
        expression.op,
        location,
      );
    case "if": {
      const condition = evaluateExpression(
        expression.condition,
        state,
        `${location}.condition`,
      );
      if (typeof condition !== "boolean") fail("type_mismatch", location);
      return evaluateExpression(
        condition ? expression.then : expression.else,
        state,
        condition ? `${location}.then` : `${location}.else`,
      );
    }
    case "coalesce":
      for (let index = 0; index < expression.args.length; index += 1) {
        const value = evaluateExpression(
          expression.args[index]!,
          state,
          `${location}.args[${index}]`,
        );
        if (value !== null) return value;
      }
      return null;
    case "sum_rows": {
      const rows = getPath(
        state.input,
        expression.rows_path,
        `${location}.rows_path`,
      );
      if (!Array.isArray(rows)) fail("type_mismatch", location);
      state.rowsVisited += rows.length;
      if (state.rowsVisited > state.compiled.limits.maximumRows) {
        fail("resource_limit_exceeded", location);
      }
      let total = new Decimal(0);
      for (let index = 0; index < rows.length; index += 1) {
        checkDeadline(state, location);
        const row = rows[index]!;
        if (
          expression.where !== undefined &&
          expression.where !== null &&
          !evaluatePredicate(
            expression.where,
            row,
            `${location}.where[${index}]`,
          )
        ) {
          continue;
        }
        total = total.add(
          toDecimal(
            getPath(
              row,
              expression.value_path,
              `${location}.value_path[${index}]`,
            ),
            location,
          ),
        );
      }
      return toDecimal(total, location);
    }
    case "date_add_days": {
      const start = parseDate(
        evaluateExpression(expression.date, state, `${location}.date`),
        location,
      );
      const days = integerDecimal(
        evaluateExpression(expression.days, state, `${location}.days`),
        location,
      );
      if (days.abs().gt(3_652_058)) fail("invalid_date", location);
      return formatDate(start + days.toNumber() * 86_400_000, location);
    }
    case "date_difference_days": {
      const start = parseDate(
        evaluateExpression(expression.start, state, `${location}.start`),
        location,
      );
      const end = parseDate(
        evaluateExpression(expression.end, state, `${location}.end`),
        location,
      );
      return new Decimal((end - start) / 86_400_000);
    }
    case "tax_pack": {
      if (state.taxPort === undefined) fail("tax_invocation_failed", location);
      const inputs: MutableJsonRecord = Object.create(
        null,
      ) as MutableJsonRecord;
      for (const key of Object.keys(expression.inputs).sort()) {
        inputs[key] = externalize(
          evaluateExpression(
            expression.inputs[key]!,
            state,
            `${location}.inputs.${key}`,
          ),
        );
      }
      try {
        const result = state.taxPort.calculate({
          context: expression.context,
          inputs,
        }) as unknown;
        checkDeadline(state, location);
        if (
          !isPlainRecord(result) ||
          Object.keys(result).sort().join(",") !==
            "outputs,packChecksum,packKey,packVersion,snapshotChecksum" ||
          !isPlainRecord(result.outputs) ||
          Object.keys(result.outputs).length > 128 ||
          Object.keys(result.outputs).some((key) => !isSafeOutputKey(key)) ||
          typeof result.packKey !== "string" ||
          !KEY_PATTERN.test(result.packKey) ||
          typeof result.packVersion !== "string" ||
          !SEMVER_PATTERN.test(result.packVersion) ||
          typeof result.packChecksum !== "string" ||
          !/^[0-9a-f]{64}$/u.test(result.packChecksum) ||
          typeof result.snapshotChecksum !== "string" ||
          !/^[0-9a-f]{64}$/u.test(result.snapshotChecksum)
        ) {
          fail("tax_invocation_failed", location);
        }
        const output = result.outputs[expression.output];
        if (output === undefined) fail("tax_invocation_failed", location);
        const validatedOutput = validateJson(output, `${location}.tax_output`);
        state.taxComponents.push(
          Object.freeze({
            context: expression.context,
            output: expression.output,
            packKey: result.packKey,
            packVersion: result.packVersion,
            packChecksum: result.packChecksum,
            snapshotChecksum: result.snapshotChecksum,
          }),
        );
        return internalize(validatedOutput);
      } catch {
        fail("tax_invocation_failed", location);
      }
    }
    case "amortized_payment": {
      const principal = integerDecimal(
        evaluateExpression(
          expression.principal_minor,
          state,
          `${location}.principal_minor`,
        ),
        location,
        0,
      );
      const annualRateBps = integerDecimal(
        evaluateExpression(
          expression.annual_rate_bps,
          state,
          `${location}.annual_rate_bps`,
        ),
        location,
        0,
      );
      const periodsPerYear = integerDecimal(
        evaluateExpression(
          expression.periods_per_year,
          state,
          `${location}.periods_per_year`,
        ),
        location,
        1,
      );
      const numberOfPeriods = integerDecimal(
        evaluateExpression(
          expression.number_of_periods,
          state,
          `${location}.number_of_periods`,
        ),
        location,
        1,
      );
      if (periodsPerYear.gt(366) || numberOfPeriods.gt(100_000)) {
        fail("resource_limit_exceeded", location);
      }
      if (principal.isZero()) return new Decimal(0);
      const periodicRate = annualRateBps.div(10_000).div(periodsPerYear);
      let payment: InstanceType<typeof Decimal>;
      try {
        payment = periodicRate.isZero()
          ? principal.div(numberOfPeriods)
          : principal
              .mul(periodicRate)
              .div(
                new Decimal(1).sub(
                  new Decimal(1).add(periodicRate).pow(numberOfPeriods.neg()),
                ),
              );
      } catch {
        fail("numeric_overflow", location);
      }
      return toDecimal(payment, location).toDecimalPlaces(
        0,
        decimalRounding(expression.rounding.mode),
      );
    }
  }
}

export function runCalculation(
  compiled: CompiledCalculationDefinition,
  input: unknown,
  options: Readonly<{
    taxPort?: CalculationTaxPort;
    now?: () => number;
    engineVersion?: string;
  }> = {},
): CalculationSnapshot {
  const normalizedInput = canonicalClone(input, "input");
  if (
    new TextEncoder().encode(canonicalJson(normalizedInput)).byteLength >
    compiled.limits.maximumInputBytes
  ) {
    fail("resource_limit_exceeded", "input");
  }
  const now = options.now ?? (() => performance.now());
  const startedAt = now();
  const state: EvaluationState = {
    compiled,
    input: internalize(normalizedInput),
    outputs: new Map(),
    evaluating: new Set(),
    taxComponents: [],
    taxPort: options.taxPort,
    startedAt,
    now,
    rowsVisited: 0,
  };
  for (const key of compiled.outputOrder) evaluateOutput(key, state);
  checkDeadline(state, "snapshot");
  const output: MutableJsonRecord = Object.create(null) as MutableJsonRecord;
  const components: Array<Readonly<{ key: string; value: CalculationJson }>> =
    [];
  for (const key of Object.keys(compiled.definition.outputs).sort()) {
    const value = externalize(state.outputs.get(key)!);
    output[key] = value;
    components.push(Object.freeze({ key, value }));
  }
  if (
    new TextEncoder().encode(canonicalJson(output)).byteLength >
    compiled.limits.maximumOutputBytes
  ) {
    fail("resource_limit_exceeded", "output");
  }
  const engineVersion = options.engineVersion ?? CALCULATION_ENGINE_VERSION;
  if (!/^[a-z0-9][a-z0-9_.-]{0,127}$/u.test(engineVersion)) {
    fail("invalid_definition", "engineVersion");
  }
  const snapshotWithoutChecksum = {
    definitionKey: compiled.definition.key,
    definitionVersion: compiled.definition.version,
    definitionChecksum: compiled.checksum,
    definition: canonicalClone(compiled.definition, "definition"),
    engineVersion,
    input: normalizedInput,
    output,
    components,
    taxComponents: state.taxComponents,
    rounding: canonicalClone(compiled.definition.rounding, "rounding"),
  } satisfies Omit<CalculationSnapshot, "checksum">;
  const checksum = sha256Hex(
    canonicalJson(validateJson(snapshotWithoutChecksum, "snapshot")),
  );
  checkDeadline(state, "snapshot");
  return deepFreeze({ ...snapshotWithoutChecksum, checksum });
}
