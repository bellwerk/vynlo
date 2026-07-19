import { describe, expect, it } from "vitest";

import {
  CalculationRuntimeError,
  canonicalJson,
  compileCalculationDefinition,
  runCalculation,
  sha256Hex,
  type CalculationExpression,
  type CalculationLimits,
} from "./runtime";

function definition(
  outputs: Readonly<Record<string, CalculationExpression | unknown>>,
  overrides: Readonly<Record<string, unknown>> = {},
): unknown {
  return {
    key: "safe-calculation",
    version: "1.0.0",
    status: "active",
    input_schema: { type: "object" },
    outputs,
    rounding: { mode: "half_up", money_minor_units: 2 },
    fixtures: ["tests/golden.json"],
    approval_refs: ["synthetic-approval"],
    ...overrides,
  };
}

function code(action: () => unknown): string | undefined {
  try {
    action();
    return undefined;
  } catch (error) {
    return error instanceof CalculationRuntimeError ? error.code : undefined;
  }
}

describe("T-CALC-001 exact typed calculation runtime", () => {
  it("executes exact arithmetic, percentage, unary operations, comparisons, branching, and output references", () => {
    const compiled = compileCalculationDefinition(
      definition({
        base: {
          op: "add",
          args: [
            { op: "field", path: "amount" },
            { op: "constant", value: "0.1" },
          ],
        },
        sum_alias: {
          op: "sum",
          args: [
            { op: "constant", value: "1.1" },
            { op: "constant", value: "2.2" },
          ],
        },
        left_fold: {
          op: "divide",
          args: [
            { op: "constant", value: "120" },
            { op: "constant", value: "3" },
            { op: "constant", value: "2" },
          ],
        },
        percentage: {
          op: "percentage",
          value: { op: "output", key: "base" },
          percentage: { op: "constant", value: "9.975" },
        },
        minimum: {
          op: "min",
          args: [
            { op: "constant", value: "3.2" },
            { op: "constant", value: "-4" },
            { op: "constant", value: "7" },
          ],
        },
        maximum: {
          op: "max",
          args: [
            { op: "constant", value: "3.2" },
            { op: "constant", value: "7" },
          ],
        },
        absolute: { op: "abs", value: { op: "constant", value: "-4.25" } },
        selected: {
          op: "if",
          condition: {
            op: "gte",
            left: { op: "output", key: "base" },
            right: { op: "constant", value: "10" },
          },
          then: { op: "constant", value: "large" },
          else: { op: "constant", value: "small" },
        },
        fallback: {
          op: "coalesce",
          args: [
            { op: "field", path: "optional" },
            { op: "constant", value: "fallback" },
          ],
        },
      }),
    );

    const snapshot = runCalculation(compiled, {
      amount: "9.9",
      optional: null,
    });

    expect(snapshot.output).toMatchObject({
      absolute: "4.25",
      base: "10",
      fallback: "fallback",
      left_fold: "20",
      maximum: "7",
      minimum: "-4",
      percentage: "0.9975",
      selected: "large",
      sum_alias: "3.3",
    });
    expect(snapshot.components.map(({ key }) => key)).toEqual(
      Object.keys(snapshot.output).sort(),
    );
  });

  it("implements every rounding mode plus floor and ceiling exactly for negative values", () => {
    const compiled = compileCalculationDefinition(
      definition({
        half_up: {
          op: "round",
          value: { op: "constant", value: "-2.5" },
          scale: 0,
          mode: "half_up",
        },
        half_even: {
          op: "round",
          value: { op: "constant", value: "-2.5" },
          scale: 0,
          mode: "half_even",
        },
        down: {
          op: "round",
          value: { op: "constant", value: "-2.9" },
          scale: 0,
          mode: "down",
        },
        up: {
          op: "round",
          value: { op: "constant", value: "-2.1" },
          scale: 0,
          mode: "up",
        },
        floor: { op: "floor", value: { op: "constant", value: "-2.1" } },
        ceil: { op: "ceil", value: { op: "constant", value: "-2.1" } },
      }),
    );
    expect(runCalculation(compiled, {}).output).toEqual({
      ceil: "-2",
      down: "-2",
      floor: "-3",
      half_even: "-2",
      half_up: "-3",
      up: "-3",
    });
  });

  it("sums bounded repeating rows through typed predicates", () => {
    const compiled = compileCalculationDefinition(
      definition({
        total: {
          op: "sum_rows",
          rows_path: "fees",
          value_path: "amount_minor",
          where: {
            all: [
              { path: "taxable", eq: true },
              { path: "financed", eq: true },
            ],
          },
        },
      }),
    );
    expect(
      runCalculation(compiled, {
        fees: [
          { amount_minor: 10, financed: true, taxable: true },
          { amount_minor: "20", financed: true, taxable: true },
          { amount_minor: 99, financed: false, taxable: true },
        ],
      }).output.total,
    ).toBe("30");
  });

  it("uses date-only UTC calendar arithmetic without timezone drift", () => {
    const compiled = compileCalculationDefinition(
      definition({
        next: {
          op: "date_add_days",
          date: { op: "field", path: "start" },
          days: { op: "constant", value: 2 },
        },
        difference: {
          op: "date_difference_days",
          start: { op: "field", path: "start" },
          end: { op: "constant", value: "2028-03-02" },
        },
      }),
    );
    expect(runCalculation(compiled, { start: "2028-02-28" }).output).toEqual({
      difference: "3",
      next: "2028-03-01",
    });
  });

  it("invokes only the injected tax port and pins its immutable evidence", () => {
    const compiled = compileCalculationDefinition(
      definition({
        gst: {
          op: "tax_pack",
          context: "vehicle_retail_sale",
          inputs: {
            eligible_taxable_consideration_minor: {
              op: "field",
              path: "base_minor",
            },
          },
          output: "gst_minor",
        },
      }),
    );
    const snapshot = runCalculation(
      compiled,
      { base_minor: "10000" },
      {
        taxPort: {
          calculate: (request) => {
            expect(request).toEqual({
              context: "vehicle_retail_sale",
              inputs: { eligible_taxable_consideration_minor: "10000" },
            });
            return {
              outputs: { gst_minor: "500" },
              packKey: "tax-ca-qc",
              packVersion: "1.0.0",
              packChecksum: "a".repeat(64),
              snapshotChecksum: "b".repeat(64),
            };
          },
        },
      },
    );
    expect(snapshot.output.gst).toBe("500");
    expect(snapshot.taxComponents).toEqual([
      {
        context: "vehicle_retail_sale",
        output: "gst_minor",
        packKey: "tax-ca-qc",
        packVersion: "1.0.0",
        packChecksum: "a".repeat(64),
        snapshotChecksum: "b".repeat(64),
      },
    ]);
  });

  it("calculates zero-rate and interest-bearing amortized payments in integer minor units", () => {
    const payment = (rate: string): CalculationExpression => ({
      op: "amortized_payment",
      principal_minor: { op: "constant", value: "100000" },
      annual_rate_bps: { op: "constant", value: rate },
      periods_per_year: { op: "constant", value: "12" },
      number_of_periods: { op: "constant", value: "12" },
      rounding: { mode: "half_up", minor_unit: 2 },
    });
    const snapshot = runCalculation(
      compileCalculationDefinition(
        definition({
          zero_rate: payment("0"),
          twelve_percent: payment("1200"),
        }),
      ),
      {},
    );
    expect(snapshot.output).toEqual({
      twelve_percent: "8885",
      zero_rate: "8333",
    });
  });

  it("produces canonical, deterministic definition and snapshot checksums", () => {
    const first = compileCalculationDefinition(
      definition({
        b: { op: "constant", value: 2 },
        a: { op: "constant", value: 1 },
      }),
    );
    const second = compileCalculationDefinition(
      definition({
        a: { value: 1, op: "constant" },
        b: { value: 2, op: "constant" },
      }),
    );
    expect(first.checksum).toBe(second.checksum);
    expect(Object.isFrozen(first.definition.outputs)).toBe(true);
    const run1 = runCalculation(first, { z: 2, a: 1 });
    const run2 = runCalculation(second, { a: 1, z: 2 });
    expect(run1).toEqual(run2);
    expect(Object.isFrozen(run1.output)).toBe(true);
    expect(run1.checksum).toMatch(/^[0-9a-f]{64}$/u);
    expect(sha256Hex(canonicalJson({ a: 1 }))).toHaveLength(64);
  });

  it("keeps the immutable content checksum stable across lifecycle and approval state", () => {
    const outputs = {
      total: { op: "constant", value: "10.00" },
    } as const;
    const draft = compileCalculationDefinition(
      definition(outputs, { approval_refs: [], status: "draft" }),
    );
    const active = compileCalculationDefinition(
      definition(outputs, {
        approval_refs: ["approval-1"],
        status: "active",
      }),
    );

    expect(active.checksum).toBe(draft.checksum);
    expect(active.definition.status).toBe("active");
    expect(active.definition.approval_refs).toEqual(["approval-1"]);
  });
});

describe("T-CALC-002 calculation abuse and resource limits fail safely", () => {
  it("rejects unknown operations, extra keys, invalid arity, missing outputs, and output cycles", () => {
    expect(
      code(() =>
        compileCalculationDefinition(
          definition({ value: { op: "eval", code: "process.env" } }),
        ),
      ),
    ).toBe("unknown_operation");
    expect(
      code(() =>
        compileCalculationDefinition(
          definition({ value: { op: "constant", value: 1, sql: "select 1" } }),
        ),
      ),
    ).toBe("invalid_expression");
    expect(
      code(() =>
        compileCalculationDefinition(
          definition({
            value: { op: "divide", args: [{ op: "constant", value: 1 }] },
          }),
        ),
      ),
    ).toBe("invalid_arity");
    expect(
      code(() =>
        compileCalculationDefinition(
          definition({ value: { op: "output", key: "absent" } }),
        ),
      ),
    ).toBe("missing_output");
    expect(
      code(() =>
        compileCalculationDefinition(
          definition({
            first: { op: "output", key: "second" },
            second: { op: "output", key: "first" },
          }),
        ),
      ),
    ).toBe("output_cycle");
  });

  it("blocks prototype paths and executable object prototypes", () => {
    expect(
      code(() =>
        compileCalculationDefinition(
          definition({
            value: { op: "field", path: "constructor.constructor" },
          }),
        ),
      ),
    ).toBe("forbidden_path");
    expect(
      code(() =>
        compileCalculationDefinition(
          definition({ constructor: { op: "constant", value: 1 } }),
        ),
      ),
    ).toBe("forbidden_path");
    const malicious = Object.create({ op: "constant", value: 1 }) as object;
    expect(
      code(() =>
        compileCalculationDefinition(definition({ value: malicious })),
      ),
    ).toBe("invalid_expression");
    expect(
      code(() =>
        runCalculation(
          compileCalculationDefinition(
            definition({ value: { op: "constant", value: 1 } }),
          ),
          JSON.parse('{"__proto__":{"polluted":true}}'),
        ),
      ),
    ).toBe("forbidden_path");
    const cyclic: Record<string, unknown> = {};
    cyclic.self = cyclic;
    expect(
      code(() =>
        runCalculation(
          compileCalculationDefinition(
            definition({ value: { op: "constant", value: 1 } }),
          ),
          cyclic,
        ),
      ),
    ).toBe("invalid_input");
    expect(({} as { polluted?: boolean }).polluted).toBeUndefined();
  });

  it("fails on missing fields, type mismatch, division by zero, invalid dates, and overflow", () => {
    const cases: Array<readonly [CalculationExpression, unknown, string]> = [
      [{ op: "field", path: "missing" }, {}, "missing_field"],
      [
        { op: "add", args: [{ op: "constant", value: "not-a-number" }] },
        {},
        "type_mismatch",
      ],
      [
        {
          op: "divide",
          args: [
            { op: "constant", value: 1 },
            { op: "constant", value: 0 },
          ],
        },
        {},
        "division_by_zero",
      ],
      [
        {
          op: "date_add_days",
          date: { op: "constant", value: "2027-02-29" },
          days: { op: "constant", value: 1 },
        },
        {},
        "invalid_date",
      ],
      [
        {
          op: "multiply",
          args: [
            { op: "constant", value: `1${"0".repeat(101)}` },
            { op: "constant", value: 10 },
          ],
        },
        {},
        "numeric_overflow",
      ],
      [
        {
          op: "add",
          args: [{ op: "constant", value: `0.${"0".repeat(100)}1` }],
        },
        {},
        "numeric_overflow",
      ],
    ];
    for (const [expression, input, expected] of cases) {
      const compiled = compileCalculationDefinition(
        definition({ value: expression }),
      );
      expect(code(() => runCalculation(compiled, input))).toBe(expected);
    }
    expect(
      code(() =>
        runCalculation(
          compileCalculationDefinition(
            definition({ value: { op: "constant", value: 1 } }),
          ),
          { unsafeFloat: 0.1 },
        ),
      ),
    ).toBe("invalid_input");
  });

  it("enforces node, depth, output, row, input-byte, and runtime boundaries at N versus N+1", () => {
    const oneNode = definition({ value: { op: "constant", value: 1 } });
    expect(() =>
      compileCalculationDefinition(oneNode, { maximumNodes: 1 }),
    ).not.toThrow();
    expect(
      code(() =>
        compileCalculationDefinition(
          definition({
            value: { op: "add", args: [{ op: "constant", value: 1 }] },
          }),
          { maximumNodes: 1 },
        ),
      ),
    ).toBe("resource_limit_exceeded");
    const predicateDefinition = definition({
      value: {
        op: "sum_rows",
        rows_path: "rows",
        value_path: "amount",
        where: { path: "included", eq: true },
      },
    });
    expect(() =>
      compileCalculationDefinition(predicateDefinition, { maximumNodes: 2 }),
    ).not.toThrow();
    expect(
      code(() =>
        compileCalculationDefinition(predicateDefinition, { maximumNodes: 1 }),
      ),
    ).toBe("resource_limit_exceeded");
    expect(() =>
      compileCalculationDefinition(oneNode, { maximumDepth: 1 }),
    ).not.toThrow();
    expect(
      code(() =>
        compileCalculationDefinition(
          definition({
            value: { op: "abs", value: { op: "constant", value: 1 } },
          }),
          { maximumDepth: 1 },
        ),
      ),
    ).toBe("resource_limit_exceeded");
    expect(() =>
      compileCalculationDefinition(oneNode, { maximumOutputs: 1 }),
    ).not.toThrow();
    expect(
      code(() =>
        compileCalculationDefinition(
          definition({
            a: { op: "constant", value: 1 },
            b: { op: "constant", value: 2 },
          }),
          { maximumOutputs: 1 },
        ),
      ),
    ).toBe("resource_limit_exceeded");

    const rowsCompiled = compileCalculationDefinition(
      definition({
        total: { op: "sum_rows", rows_path: "rows", value_path: "amount" },
      }),
      { maximumRows: 2 },
    );
    expect(
      runCalculation(rowsCompiled, { rows: [{ amount: 1 }, { amount: 2 }] })
        .output.total,
    ).toBe("3");
    expect(
      code(() =>
        runCalculation(rowsCompiled, {
          rows: [{ amount: 1 }, { amount: 2 }, { amount: 3 }],
        }),
      ),
    ).toBe("resource_limit_exceeded");

    const inputCompiled = compileCalculationDefinition(oneNode, {
      maximumInputBytes: 10,
    });
    expect(() => runCalculation(inputCompiled, { a: "1" })).not.toThrow();
    expect(code(() => runCalculation(inputCompiled, { a: "123" }))).toBe(
      "resource_limit_exceeded",
    );

    const outputAtBoundary = compileCalculationDefinition(
      definition({ value: { op: "constant", value: "1" } }),
      { maximumOutputBytes: 13 },
    );
    expect(runCalculation(outputAtBoundary, {}).output.value).toBe("1");
    const outputOverBoundary = compileCalculationDefinition(
      definition({ value: { op: "constant", value: "12" } }),
      { maximumOutputBytes: 13 },
    );
    expect(code(() => runCalculation(outputOverBoundary, {}))).toBe(
      "resource_limit_exceeded",
    );

    const boundaryTimes = [0, 1, 1];
    expect(() =>
      runCalculation(
        compileCalculationDefinition(oneNode, { maximumRuntimeMs: 1 }),
        {},
        { now: () => boundaryTimes.shift() ?? 1 },
      ),
    ).not.toThrow();
    let tick = 0;
    const runtimeCompiled = compileCalculationDefinition(oneNode, {
      maximumRuntimeMs: 1,
    });
    expect(
      code(() =>
        runCalculation(
          runtimeCompiled,
          {},
          { now: () => (tick++ === 0 ? 0 : 2) },
        ),
      ),
    ).toBe("resource_limit_exceeded");
  });

  it("converts tax-port failures and malformed evidence into one safe error", () => {
    const compiled = compileCalculationDefinition(
      definition({
        value: {
          op: "tax_pack",
          context: "vehicle_retail_sale",
          inputs: {},
          output: "gst_minor",
        },
      }),
    );
    expect(code(() => runCalculation(compiled, {}))).toBe(
      "tax_invocation_failed",
    );
    expect(
      code(() =>
        runCalculation(
          compiled,
          {},
          {
            taxPort: {
              calculate: () => undefined as never,
            },
          },
        ),
      ),
    ).toBe("tax_invocation_failed");
    expect(
      code(() =>
        runCalculation(
          compiled,
          {},
          {
            taxPort: {
              calculate: () => ({
                outputs: { gst_minor: "10" },
                packKey: "pack",
                packVersion: "1.0.0",
                packChecksum: "not-a-checksum",
                snapshotChecksum: "b".repeat(64),
              }),
            },
          },
        ),
      ),
    ).toBe("tax_invocation_failed");
  });

  it("validates every configured limit as a positive integer", () => {
    for (const key of Object.keys({
      maximumDepth: 1,
      maximumInputBytes: 1,
      maximumNodes: 1,
      maximumOutputBytes: 1,
      maximumOutputs: 1,
      maximumRows: 1,
      maximumRuntimeMs: 1,
    } satisfies CalculationLimits)) {
      expect(
        code(() =>
          compileCalculationDefinition(oneOutput(), {
            [key]: 0,
          } as Partial<CalculationLimits>),
        ),
      ).toBe("invalid_definition");
    }
  });
});

function oneOutput(): unknown {
  return definition({ value: { op: "constant", value: 1 } });
}
