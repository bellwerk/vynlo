# @vynlo/calculations

Tenant-neutral, deterministic calculation runtime for `M4-CALC-AC-001..005`.
It is an in-process modular-monolith package, not a separate service and not a
place for tenant formulas.

## Runtime contract

`compileCalculationDefinition` accepts an exact-key, discriminated JSON AST and
returns an immutable compiled definition, dependency order, limits, and SHA-256
checksum. `runCalculation` evaluates that compiled definition with Decimal.js;
financial results never use binary floating-point. JavaScript numeric inputs are
limited to safe integers. Fractional values must be decimal strings.

The runtime supports constants, fields, output references, add/sum/subtract,
multiply/divide, min/max/absolute, percentages, explicit rounding, floor/ceil,
comparisons, conditions, coalesce, bounded row totals with typed predicates,
UTC date-only addition/difference, an injected tax-pack port, and a generic
amortized-payment primitive.

Output references are topologically ordered. Missing references, cycles,
forbidden prototype paths, type errors, division by zero, invalid dates,
overflow, unknown operations, and resource exhaustion raise
`CalculationRuntimeError` with a stable machine code and no input value in the
message.

## Resource and evidence boundary

`DEFAULT_CALCULATION_LIMITS` bounds AST depth, AST nodes, output count, output
bytes, input bytes, visited rows, and execution time. Callers may provide
smaller or larger positive integer limits when compiling a trusted definition.

Every successful run returns a canonical snapshot containing the exact
definition, engine version, definition checksum, normalized input, ordered
components, outputs, rounding policy, injected tax-version evidence, and a
snapshot checksum. Callers that persist an official calculation must append
that snapshot rather than reconstructing it later.

The package performs no SQL, filesystem, shell, module-loading, or network
operation. Tax is available only through the injected `CalculationTaxPort`.

## Verification

`src/runtime.test.ts` implements `T-CALC-001` and `T-CALC-002`, including exact
arithmetic, deterministic evidence, every supported primitive, abuse cases, and
N versus N+1 resource boundaries.
