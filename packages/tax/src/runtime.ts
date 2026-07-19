import {
  Decimal,
  canonicalJson,
  sha256Hex,
  type CalculationJson,
  type CalculationTaxPort,
  type TaxInvocationResult,
} from "@vynlo/calculations";

export const TAX_ENGINE_VERSION = "vynlo-tax-v1" as const;

export type TaxPackStatus =
  "draft" | "validated" | "test_passed" | "approved" | "active" | "retired";
export type TaxRoundingMode = "HALF_UP" | "HALF_EVEN" | "DOWN" | "UP";

export interface TaxPackSource {
  readonly key: string;
  readonly authority: string;
  readonly url: string;
  readonly accessed_on: string;
}

export interface TaxRuleDefinition {
  readonly key: string;
  readonly labels: Readonly<{ en: string; fr: string }>;
  readonly rate: string;
  readonly taxable_base: "eligible_taxable_consideration";
  readonly gst_included_in_base?: boolean;
  readonly source_ref: string;
}

export interface TaxPackDefinition {
  readonly key: string;
  readonly version: string;
  readonly jurisdiction: string;
  readonly contexts: readonly string[];
  readonly effective_from: string;
  readonly effective_to: string | null;
  readonly sources: readonly TaxPackSource[];
  readonly rules: Readonly<{
    currency: string;
    rounding: Readonly<{
      mode: TaxRoundingMode;
      scale: number;
      stage: "tax_total_per_tax_type";
    }>;
    taxes: readonly TaxRuleDefinition[];
    trade_in: Readonly<{
      strategy: "conditional_credit_reduces_taxable_consideration";
      requires_explicit_eligibility_inputs: true;
      lien_payoff_is_not_automatically_tax_credit: true;
    }>;
    unsupported_without_override: readonly string[];
  }>;
  readonly golden_tests: readonly string[];
  readonly activation_status: TaxPackStatus;
  readonly approval_refs: readonly string[];
}

export interface CompiledTaxPack {
  readonly checksum: string;
  readonly definition: Readonly<TaxPackDefinition>;
}

export type TaxErrorCode =
  | "ambiguous_tax_pack"
  | "invalid_date"
  | "invalid_input"
  | "invalid_pack"
  | "numeric_overflow"
  | "tax_override_denied"
  | "tax_pack_unavailable"
  | "trade_in_eligibility_required"
  | "unsupported_transaction";

export class TaxRuntimeError extends Error {
  readonly code: TaxErrorCode;
  readonly location: string;

  constructor(code: TaxErrorCode, location = "tax") {
    super(`Tax calculation failed safely: ${code}.`);
    this.name = "TaxRuntimeError";
    this.code = code;
    this.location = location;
  }
}

export type TaxAvailabilityGate =
  | "approval_missing"
  | "context_unsupported"
  | "currency_unsupported"
  | "effective_date_mismatch"
  | "jurisdiction_mismatch"
  | "pack_not_active"
  | "pack_retired";

export interface TaxPackSelector {
  readonly jurisdiction: string;
  readonly context: string;
  readonly transactionDate: string;
  readonly currency: string;
  readonly usage: "preview" | "official";
}

export interface TaxAvailabilityDecision {
  readonly state:
    "available_for_preview" | "available_for_official" | "unavailable";
  readonly available: boolean;
  readonly gates: readonly TaxAvailabilityGate[];
  readonly packKey: string;
  readonly packVersion: string;
  readonly packChecksum: string;
}

export interface TaxTradeInEligibility {
  readonly explicitly_confirmed: boolean;
  readonly review_reference: string;
}

export interface TaxOverrideRequest {
  readonly kind: "trade_in_eligibility";
  readonly permissionKey: "tax.override";
  readonly permissionGranted: boolean;
  readonly recentStrongAuth: boolean;
  readonly reason: string;
  readonly reviewReference: string;
}

export interface TaxCalculationRequest {
  readonly jurisdiction: string;
  readonly context: string;
  readonly transactionDate: string;
  readonly currency: string;
  readonly input: Readonly<{
    readonly vehicle_price_minor?: string | number;
    readonly taxable_fees_minor?: string | number;
    readonly taxable_discounts_minor?: string | number;
    readonly non_taxable_fees_minor?: string | number;
    readonly non_taxable_discounts_minor?: string | number;
    readonly eligible_trade_in_credit_minor?: string | number;
    readonly trade_in_eligibility?: TaxTradeInEligibility;
    readonly eligible_taxable_consideration_minor?: string | number;
    readonly scenario?: string;
  }>;
  readonly override?: TaxOverrideRequest;
}

export interface TaxCalculationOutput {
  readonly eligible_taxable_consideration_minor: string;
  readonly non_taxable_fees_minor: string;
  readonly total_tax_minor: string;
  readonly net_cash_consideration_before_payments_minor: string;
  readonly [key: string]: string;
}

export interface TaxCalculationSnapshot {
  readonly packKey: string;
  readonly packVersion: string;
  readonly packChecksum: string;
  readonly pack: CalculationJson;
  readonly engineVersion: string;
  readonly jurisdiction: string;
  readonly context: string;
  readonly transactionDate: string;
  readonly currency: string;
  readonly input: CalculationJson;
  readonly output: TaxCalculationOutput;
  readonly override: null | Readonly<{
    kind: "trade_in_eligibility";
    permissionKey: "tax.override";
    permissionGranted: true;
    recentStrongAuth: true;
    reason: string;
    reviewReference: string;
  }>;
  readonly checksum: string;
}

export interface TaxGoldenCaseResult {
  readonly caseId: string;
  readonly passed: boolean;
  readonly mismatches: readonly string[];
  readonly snapshot: TaxCalculationSnapshot;
}

const KEY_PATTERN = /^[a-z][a-z0-9-]{1,127}$/u;
const MACHINE_KEY_PATTERN = /^[a-z][a-z0-9_]{0,127}$/u;
const SEMVER_PATTERN = /^\d+\.\d+\.\d+$/u;
const JURISDICTION_PATTERN = /^[A-Z]{2}(?:-[A-Z0-9]{1,3})?$/u;
const CURRENCY_PATTERN = /^[A-Z]{3}$/u;
const CHECKSUM_PATTERN = /^[0-9a-f]{64}$/u;
const INTEGER_PATTERN = /^(?:0|[1-9]\d{0,18})$/u;
const MAX_MINOR_VALUE = "9223372036854775807";
const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/u;
const GOLDEN_PATH_PATTERN =
  /^tests\/(?!\.\.(?:\/|$))(?!.*\/\.\.(?:\/|$))[A-Za-z0-9._/-]+\.json$/u;
const RESERVED_TAX_OUTPUT_KEYS = new Set([
  "eligible_taxable_consideration",
  "non_taxable_fees",
  "total_tax",
  "net_cash_consideration_before_payments",
]);

function fail(code: TaxErrorCode, location?: string): never {
  throw new TaxRuntimeError(code, location);
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function exactKeys(
  value: Record<string, unknown>,
  required: readonly string[],
  optional: readonly string[],
  location: string,
  errorCode: TaxErrorCode = "invalid_pack",
): void {
  const allowed = new Set([...required, ...optional]);
  if (
    required.some((key) => !Object.hasOwn(value, key)) ||
    Object.keys(value).some((key) => !allowed.has(key))
  ) {
    fail(errorCode, location);
  }
}

function parseDate(value: unknown, location: string): string {
  if (typeof value !== "string") fail("invalid_date", location);
  const match = DATE_PATTERN.exec(value);
  if (!match) fail("invalid_date", location);
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(0);
  date.setUTCHours(0, 0, 0, 0);
  date.setUTCFullYear(year, month - 1, day);
  if (
    year < 1 ||
    year > 9999 ||
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    fail("invalid_date", location);
  }
  return value;
}

function validatedUrl(value: unknown, location: string): string {
  if (typeof value !== "string" || value.length > 2_000)
    fail("invalid_pack", location);
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    fail("invalid_pack", location);
  }
  if (url.protocol !== "https:" || url.username !== "" || url.password !== "") {
    fail("invalid_pack", location);
  }
  return url.toString();
}

function parseMinor(
  value: unknown,
  location: string,
): InstanceType<typeof Decimal> {
  const text =
    typeof value === "number" && Number.isSafeInteger(value)
      ? value.toString()
      : typeof value === "string"
        ? value
        : "";
  if (!INTEGER_PATTERN.test(text)) fail("invalid_input", location);
  let amount: InstanceType<typeof Decimal>;
  try {
    amount = new Decimal(text);
  } catch {
    fail("numeric_overflow", location);
  }
  if (amount.gt(MAX_MINOR_VALUE)) fail("numeric_overflow", location);
  return amount;
}

function boundedMinor(
  value: InstanceType<typeof Decimal>,
  location: string,
): InstanceType<typeof Decimal> {
  if (
    !value.isFinite() ||
    !value.isInteger() ||
    value.isNegative() ||
    value.gt(MAX_MINOR_VALUE)
  ) {
    fail("numeric_overflow", location);
  }
  return value;
}

function roundingMode(
  mode: TaxRoundingMode,
): 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 {
  switch (mode) {
    case "HALF_UP":
      return Decimal.ROUND_HALF_UP;
    case "HALF_EVEN":
      return Decimal.ROUND_HALF_EVEN;
    case "DOWN":
      return Decimal.ROUND_DOWN;
    case "UP":
      return Decimal.ROUND_UP;
  }
}

function canonicalRecord(value: unknown): CalculationJson {
  return JSON.parse(canonicalJson(value as CalculationJson)) as CalculationJson;
}

function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

export function compileTaxPack(value: unknown): CompiledTaxPack {
  if (!isPlainRecord(value)) fail("invalid_pack");
  exactKeys(
    value,
    [
      "key",
      "version",
      "jurisdiction",
      "contexts",
      "effective_from",
      "effective_to",
      "sources",
      "rules",
      "golden_tests",
      "activation_status",
      "approval_refs",
    ],
    [],
    "pack",
  );
  if (
    typeof value.key !== "string" ||
    !KEY_PATTERN.test(value.key) ||
    typeof value.version !== "string" ||
    !SEMVER_PATTERN.test(value.version) ||
    typeof value.jurisdiction !== "string" ||
    !JURISDICTION_PATTERN.test(value.jurisdiction) ||
    !Array.isArray(value.contexts) ||
    value.contexts.length < 1 ||
    value.contexts.length > 64 ||
    value.contexts.some(
      (context) =>
        typeof context !== "string" || !MACHINE_KEY_PATTERN.test(context),
    ) ||
    new Set(value.contexts).size !== value.contexts.length ||
    !Array.isArray(value.sources) ||
    value.sources.length < 1 ||
    value.sources.length > 64 ||
    !Array.isArray(value.golden_tests) ||
    value.golden_tests.length < 1 ||
    value.golden_tests.length > 1_000 ||
    value.golden_tests.some(
      (item) => typeof item !== "string" || !GOLDEN_PATH_PATTERN.test(item),
    ) ||
    ![
      "draft",
      "validated",
      "test_passed",
      "approved",
      "active",
      "retired",
    ].includes(value.activation_status as string) ||
    !Array.isArray(value.approval_refs) ||
    value.approval_refs.length > 128 ||
    value.approval_refs.some(
      (item) =>
        typeof item !== "string" || item.length < 1 || item.length > 200,
    ) ||
    !isPlainRecord(value.rules) ||
    new Set(value.golden_tests).size !== value.golden_tests.length ||
    new Set(value.approval_refs).size !== value.approval_refs.length
  ) {
    fail("invalid_pack");
  }
  const effectiveFrom = parseDate(value.effective_from, "effective_from");
  const effectiveTo =
    value.effective_to === null
      ? null
      : parseDate(value.effective_to, "effective_to");
  if (effectiveTo !== null && effectiveTo < effectiveFrom)
    fail("invalid_pack", "effective_to");
  if (
    ["approved", "active"].includes(value.activation_status as string) &&
    value.approval_refs.length < 1
  ) {
    fail("invalid_pack", "approval_refs");
  }

  const sources = (value.sources as unknown[]).map(
    (source, index): TaxPackSource => {
      if (!isPlainRecord(source)) fail("invalid_pack", `sources[${index}]`);
      exactKeys(
        source,
        ["key", "authority", "url", "accessed_on"],
        [],
        `sources[${index}]`,
      );
      if (
        typeof source.key !== "string" ||
        !MACHINE_KEY_PATTERN.test(source.key) ||
        typeof source.authority !== "string" ||
        source.authority.trim().length < 1 ||
        source.authority.length > 200
      ) {
        fail("invalid_pack", `sources[${index}]`);
      }
      return {
        key: source.key,
        authority: source.authority.trim(),
        url: validatedUrl(source.url, `sources[${index}].url`),
        accessed_on: parseDate(
          source.accessed_on,
          `sources[${index}].accessed_on`,
        ),
      };
    },
  );
  if (new Set(sources.map(({ key }) => key)).size !== sources.length) {
    fail("invalid_pack", "sources");
  }
  const sourceKeys = new Set(sources.map(({ key }) => key));

  const rules = value.rules;
  exactKeys(
    rules,
    [
      "currency",
      "rounding",
      "taxes",
      "trade_in",
      "unsupported_without_override",
    ],
    [],
    "rules",
  );
  if (
    typeof rules.currency !== "string" ||
    !CURRENCY_PATTERN.test(rules.currency) ||
    !isPlainRecord(rules.rounding) ||
    !Array.isArray(rules.taxes) ||
    rules.taxes.length < 1 ||
    rules.taxes.length > 32 ||
    !isPlainRecord(rules.trade_in) ||
    !Array.isArray(rules.unsupported_without_override) ||
    rules.unsupported_without_override.length > 128 ||
    rules.unsupported_without_override.some(
      (item) => typeof item !== "string" || !MACHINE_KEY_PATTERN.test(item),
    ) ||
    new Set(rules.unsupported_without_override).size !==
      rules.unsupported_without_override.length
  ) {
    fail("invalid_pack", "rules");
  }
  exactKeys(rules.rounding, ["mode", "scale", "stage"], [], "rules.rounding");
  if (
    !["HALF_UP", "HALF_EVEN", "DOWN", "UP"].includes(
      rules.rounding.mode as string,
    ) ||
    !Number.isInteger(rules.rounding.scale) ||
    (rules.rounding.scale as number) < 0 ||
    (rules.rounding.scale as number) > 6 ||
    rules.rounding.stage !== "tax_total_per_tax_type"
  ) {
    fail("invalid_pack", "rules.rounding");
  }
  exactKeys(
    rules.trade_in,
    [
      "strategy",
      "requires_explicit_eligibility_inputs",
      "lien_payoff_is_not_automatically_tax_credit",
    ],
    [],
    "rules.trade_in",
  );
  if (
    rules.trade_in.strategy !==
      "conditional_credit_reduces_taxable_consideration" ||
    rules.trade_in.requires_explicit_eligibility_inputs !== true ||
    rules.trade_in.lien_payoff_is_not_automatically_tax_credit !== true
  ) {
    fail("invalid_pack", "rules.trade_in");
  }
  const taxes = (rules.taxes as unknown[]).map(
    (tax, index): TaxRuleDefinition => {
      if (!isPlainRecord(tax)) fail("invalid_pack", `rules.taxes[${index}]`);
      exactKeys(
        tax,
        ["key", "labels", "rate", "taxable_base", "source_ref"],
        ["gst_included_in_base"],
        `rules.taxes[${index}]`,
      );
      if (
        typeof tax.key !== "string" ||
        !MACHINE_KEY_PATTERN.test(tax.key) ||
        RESERVED_TAX_OUTPUT_KEYS.has(tax.key) ||
        !isPlainRecord(tax.labels) ||
        Object.keys(tax.labels).sort().join(",") !== "en,fr" ||
        Object.values(tax.labels).some(
          (label) =>
            typeof label !== "string" ||
            label.trim().length < 1 ||
            label.length > 100,
        ) ||
        typeof tax.rate !== "string" ||
        !/^0(?:\.\d{1,12})?$|^1(?:\.0+)?$/u.test(tax.rate) ||
        tax.taxable_base !== "eligible_taxable_consideration" ||
        typeof tax.source_ref !== "string" ||
        !sourceKeys.has(tax.source_ref) ||
        (tax.gst_included_in_base !== undefined &&
          typeof tax.gst_included_in_base !== "boolean")
      ) {
        fail("invalid_pack", `rules.taxes[${index}]`);
      }
      return {
        key: tax.key,
        labels: { en: tax.labels.en as string, fr: tax.labels.fr as string },
        rate: tax.rate,
        taxable_base: "eligible_taxable_consideration",
        source_ref: tax.source_ref,
        ...(tax.gst_included_in_base === undefined
          ? {}
          : { gst_included_in_base: tax.gst_included_in_base }),
      };
    },
  );
  if (new Set(taxes.map(({ key }) => key)).size !== taxes.length) {
    fail("invalid_pack", "rules.taxes");
  }

  const definition: TaxPackDefinition = {
    key: value.key,
    version: value.version,
    jurisdiction: value.jurisdiction,
    contexts: Object.freeze([...(value.contexts as string[])]),
    effective_from: effectiveFrom,
    effective_to: effectiveTo,
    sources: Object.freeze(sources),
    rules: Object.freeze({
      currency: rules.currency,
      rounding: Object.freeze({
        mode: rules.rounding.mode as TaxRoundingMode,
        scale: rules.rounding.scale as number,
        stage: "tax_total_per_tax_type" as const,
      }),
      taxes: Object.freeze(taxes),
      trade_in: Object.freeze({
        strategy: "conditional_credit_reduces_taxable_consideration" as const,
        requires_explicit_eligibility_inputs: true as const,
        lien_payoff_is_not_automatically_tax_credit: true as const,
      }),
      unsupported_without_override: Object.freeze([
        ...(rules.unsupported_without_override as string[]),
      ]),
    }),
    golden_tests: Object.freeze([...(value.golden_tests as string[])]),
    activation_status: value.activation_status as TaxPackStatus,
    approval_refs: Object.freeze([...(value.approval_refs as string[])]),
  };
  const artifactContent = {
    key: definition.key,
    version: definition.version,
    jurisdiction: definition.jurisdiction,
    contexts: definition.contexts,
    effective_from: definition.effective_from,
    effective_to: definition.effective_to,
    sources: definition.sources,
    rules: definition.rules,
    golden_tests: definition.golden_tests,
  };
  // Activation state and approval IDs are lifecycle evidence. The artifact
  // checksum remains bound to immutable tax content while those gates change.
  const checksum = sha256Hex(canonicalJson(canonicalRecord(artifactContent)));
  return Object.freeze({ checksum, definition: deepFreeze(definition) });
}

function validateSelector(selector: TaxPackSelector): void {
  if (!isPlainRecord(selector)) fail("invalid_input", "selector");
  const keys = Object.keys(selector).sort().join(",");
  if (
    keys !== "context,currency,jurisdiction,transactionDate,usage" ||
    !JURISDICTION_PATTERN.test(selector.jurisdiction) ||
    !MACHINE_KEY_PATTERN.test(selector.context) ||
    !CURRENCY_PATTERN.test(selector.currency) ||
    !["preview", "official"].includes(selector.usage)
  ) {
    fail("invalid_input", "selector");
  }
  parseDate(selector.transactionDate, "selector.transactionDate");
}

export function decideTaxPackAvailability(
  pack: CompiledTaxPack,
  selector: TaxPackSelector,
): TaxAvailabilityDecision {
  validateSelector(selector);
  const definition = pack.definition;
  const gates: TaxAvailabilityGate[] = [];
  if (definition.jurisdiction !== selector.jurisdiction)
    gates.push("jurisdiction_mismatch");
  if (!definition.contexts.includes(selector.context))
    gates.push("context_unsupported");
  if (definition.rules.currency !== selector.currency)
    gates.push("currency_unsupported");
  if (
    selector.transactionDate < definition.effective_from ||
    (definition.effective_to !== null &&
      selector.transactionDate > definition.effective_to)
  ) {
    gates.push("effective_date_mismatch");
  }
  if (definition.activation_status === "retired") gates.push("pack_retired");
  const structuralGates = gates.length;
  if (selector.usage === "official") {
    if (definition.activation_status !== "active")
      gates.push("pack_not_active");
    if (definition.approval_refs.length < 1) gates.push("approval_missing");
  }
  const uniqueGates = Object.freeze([...new Set(gates)]);
  const available = uniqueGates.length === 0;
  return Object.freeze({
    state: available
      ? selector.usage === "official"
        ? "available_for_official"
        : "available_for_preview"
      : selector.usage === "preview" &&
          structuralGates === 0 &&
          definition.activation_status !== "retired"
        ? "available_for_preview"
        : "unavailable",
    available:
      available ||
      (selector.usage === "preview" &&
        structuralGates === 0 &&
        definition.activation_status !== "retired"),
    gates: uniqueGates,
    packKey: definition.key,
    packVersion: definition.version,
    packChecksum: pack.checksum,
  });
}

export function selectTaxPack(
  packs: readonly CompiledTaxPack[],
  selector: TaxPackSelector,
): CompiledTaxPack {
  validateSelector(selector);
  const matching = packs.filter(
    (pack) => decideTaxPackAvailability(pack, selector).available,
  );
  if (matching.length < 1) fail("tax_pack_unavailable");
  if (matching.length > 1) fail("ambiguous_tax_pack");
  return matching[0]!;
}

function validateRequest(request: TaxCalculationRequest): void {
  if (!isPlainRecord(request)) fail("invalid_input", "request");
  const keys = Object.keys(request).sort().join(",");
  if (
    ![
      "context,currency,input,jurisdiction,transactionDate",
      "context,currency,input,jurisdiction,override,transactionDate",
    ].includes(keys) ||
    !JURISDICTION_PATTERN.test(request.jurisdiction) ||
    !MACHINE_KEY_PATTERN.test(request.context) ||
    !CURRENCY_PATTERN.test(request.currency) ||
    !isPlainRecord(request.input)
  ) {
    fail("invalid_input", "request");
  }
  parseDate(request.transactionDate, "request.transactionDate");
  const inputKeys = Object.keys(request.input);
  const allowedInputKeys = new Set([
    "vehicle_price_minor",
    "taxable_fees_minor",
    "taxable_discounts_minor",
    "non_taxable_fees_minor",
    "non_taxable_discounts_minor",
    "eligible_trade_in_credit_minor",
    "trade_in_eligibility",
    "eligible_taxable_consideration_minor",
    "scenario",
  ]);
  if (inputKeys.some((key) => !allowedInputKeys.has(key)))
    fail("invalid_input", "request.input");
  const eligibility = request.input.trade_in_eligibility;
  if (eligibility !== undefined) {
    if (!isPlainRecord(eligibility)) {
      fail("invalid_input", "request.input.trade_in_eligibility");
    }
    exactKeys(
      eligibility,
      ["explicitly_confirmed", "review_reference"],
      [],
      "request.input.trade_in_eligibility",
      "invalid_input",
    );
    if (
      typeof eligibility.explicitly_confirmed !== "boolean" ||
      typeof eligibility.review_reference !== "string" ||
      eligibility.review_reference.trim().length < 3 ||
      eligibility.review_reference.length > 200
    ) {
      fail("invalid_input", "request.input.trade_in_eligibility");
    }
  }
  if (
    request.input.scenario !== undefined &&
    (typeof request.input.scenario !== "string" ||
      !MACHINE_KEY_PATTERN.test(request.input.scenario))
  ) {
    fail("invalid_input", "request.input.scenario");
  }
  if (request.override !== undefined) {
    if (!isPlainRecord(request.override))
      fail("invalid_input", "request.override");
    const overrideKeys = Object.keys(request.override).sort().join(",");
    if (
      overrideKeys !==
        "kind,permissionGranted,permissionKey,reason,recentStrongAuth,reviewReference" ||
      request.override.kind !== "trade_in_eligibility" ||
      request.override.permissionKey !== "tax.override"
    ) {
      fail("invalid_input", "request.override");
    }
  }
}

function approvedOverride(
  request: TaxCalculationRequest,
  credit: InstanceType<typeof Decimal>,
): TaxCalculationSnapshot["override"] {
  const eligibility = request.input.trade_in_eligibility;
  if (credit.isZero()) {
    if (request.override !== undefined) fail("invalid_input", "override");
    return null;
  }
  if (
    eligibility?.explicitly_confirmed === true &&
    typeof eligibility.review_reference === "string" &&
    eligibility.review_reference.trim().length >= 3 &&
    eligibility.review_reference.length <= 200
  ) {
    if (request.override !== undefined) fail("invalid_input", "override");
    return null;
  }
  const override = request.override;
  if (override === undefined) fail("trade_in_eligibility_required");
  if (
    override.permissionGranted !== true ||
    override.permissionKey !== "tax.override" ||
    override.recentStrongAuth !== true ||
    typeof override.reason !== "string" ||
    override.reason.trim().length < 3 ||
    override.reason.length > 2_000 ||
    typeof override.reviewReference !== "string" ||
    override.reviewReference.trim().length < 3 ||
    override.reviewReference.length > 200
  ) {
    fail("tax_override_denied");
  }
  return Object.freeze({
    kind: "trade_in_eligibility" as const,
    permissionKey: "tax.override" as const,
    permissionGranted: true as const,
    recentStrongAuth: true as const,
    reason: override.reason.trim(),
    reviewReference: override.reviewReference.trim(),
  });
}

export function executeTaxCalculation(
  pack: CompiledTaxPack,
  request: TaxCalculationRequest,
): TaxCalculationSnapshot {
  validateRequest(request);
  const decision = decideTaxPackAvailability(pack, {
    jurisdiction: request.jurisdiction,
    context: request.context,
    transactionDate: request.transactionDate,
    currency: request.currency,
    usage: "preview",
  });
  if (!decision.available) fail("tax_pack_unavailable");
  if (request.input.scenario !== undefined) {
    if (
      pack.definition.rules.unsupported_without_override.includes(
        request.input.scenario,
      )
    ) {
      fail("unsupported_transaction");
    }
    fail("invalid_input", "request.input.scenario");
  }
  const hasDirectBase =
    request.input.eligible_taxable_consideration_minor !== undefined;
  if (
    hasDirectBase &&
    [
      request.input.vehicle_price_minor,
      request.input.taxable_fees_minor,
      request.input.taxable_discounts_minor,
      request.input.eligible_trade_in_credit_minor,
      request.input.trade_in_eligibility,
    ].some((value) => value !== undefined)
  ) {
    fail("invalid_input", "request.input");
  }
  if (!hasDirectBase && request.input.vehicle_price_minor === undefined) {
    fail("invalid_input", "request.input.vehicle_price_minor");
  }
  const nonTaxableFees = parseMinor(
    request.input.non_taxable_fees_minor ?? 0,
    "input.non_taxable_fees_minor",
  );
  const nonTaxableDiscounts = parseMinor(
    request.input.non_taxable_discounts_minor ?? 0,
    "input.non_taxable_discounts_minor",
  );
  const nonTaxableConsideration = boundedMinor(
    Decimal.max(nonTaxableFees.sub(nonTaxableDiscounts), 0),
    "output.non_taxable_fees_minor",
  );
  const credit = parseMinor(
    hasDirectBase ? 0 : (request.input.eligible_trade_in_credit_minor ?? 0),
    "input.eligible_trade_in_credit_minor",
  );
  const override = approvedOverride(request, credit);
  let base: InstanceType<typeof Decimal>;
  let normalizedInput: CalculationJson;
  if (hasDirectBase) {
    base = parseMinor(
      request.input.eligible_taxable_consideration_minor,
      "input.eligible_taxable_consideration_minor",
    );
    normalizedInput = {
      eligible_taxable_consideration_minor: base.toFixed(0),
      non_taxable_fees_minor: nonTaxableFees.toFixed(0),
      ...(request.input.non_taxable_discounts_minor === undefined
        ? {}
        : {
            non_taxable_discounts_minor: nonTaxableDiscounts.toFixed(0),
          }),
    };
  } else {
    const vehiclePrice = parseMinor(
      request.input.vehicle_price_minor,
      "input.vehicle_price_minor",
    );
    const taxableFees = parseMinor(
      request.input.taxable_fees_minor ?? 0,
      "input.taxable_fees_minor",
    );
    const taxableDiscounts = parseMinor(
      request.input.taxable_discounts_minor ?? 0,
      "input.taxable_discounts_minor",
    );
    base = boundedMinor(
      Decimal.max(
        vehiclePrice.add(taxableFees).sub(taxableDiscounts).sub(credit),
        0,
      ),
      "output.eligible_taxable_consideration_minor",
    );
    normalizedInput = {
      vehicle_price_minor: vehiclePrice.toFixed(0),
      taxable_fees_minor: taxableFees.toFixed(0),
      ...(request.input.taxable_discounts_minor === undefined
        ? {}
        : { taxable_discounts_minor: taxableDiscounts.toFixed(0) }),
      non_taxable_fees_minor: nonTaxableFees.toFixed(0),
      ...(request.input.non_taxable_discounts_minor === undefined
        ? {}
        : {
            non_taxable_discounts_minor: nonTaxableDiscounts.toFixed(0),
          }),
      eligible_trade_in_credit_minor: credit.toFixed(0),
      trade_in_eligibility:
        request.input.trade_in_eligibility === undefined
          ? null
          : {
              explicitly_confirmed:
                request.input.trade_in_eligibility.explicitly_confirmed,
              review_reference:
                request.input.trade_in_eligibility.review_reference,
            },
    };
  }
  const outputs: Record<string, string> = Object.create(null) as Record<
    string,
    string
  >;
  let totalTax = new Decimal(0);
  for (const tax of pack.definition.rules.taxes) {
    const taxBase =
      tax.gst_included_in_base === true ? base.add(totalTax) : base;
    const amount = boundedMinor(
      taxBase
        .mul(new Decimal(tax.rate))
        .toDecimalPlaces(0, roundingMode(pack.definition.rules.rounding.mode)),
      `output.${tax.key}_minor`,
    );
    outputs[`${tax.key}_minor`] = amount.toFixed(0);
    totalTax = boundedMinor(totalTax.add(amount), "output.total_tax_minor");
  }
  outputs.eligible_taxable_consideration_minor = base.toFixed(0);
  outputs.non_taxable_fees_minor = nonTaxableConsideration.toFixed(0);
  outputs.total_tax_minor = totalTax.toFixed(0);
  outputs.net_cash_consideration_before_payments_minor = boundedMinor(
    base.add(nonTaxableConsideration).add(totalTax),
    "output.net_cash_consideration_before_payments_minor",
  ).toFixed(0);
  const output = Object.freeze(outputs) as TaxCalculationOutput;
  const withoutChecksum = {
    packKey: pack.definition.key,
    packVersion: pack.definition.version,
    packChecksum: pack.checksum,
    pack: canonicalRecord(pack.definition),
    engineVersion: TAX_ENGINE_VERSION,
    jurisdiction: request.jurisdiction,
    context: request.context,
    transactionDate: request.transactionDate,
    currency: request.currency,
    input: normalizedInput,
    output,
    override,
  } satisfies Omit<TaxCalculationSnapshot, "checksum">;
  const checksum = sha256Hex(canonicalJson(canonicalRecord(withoutChecksum)));
  return deepFreeze({ ...withoutChecksum, checksum });
}

function expectedValue(value: unknown): string {
  return parseMinor(value, "golden.expected").toFixed(0);
}

export function runTaxGoldenCases(
  pack: CompiledTaxPack,
  cases: readonly unknown[],
  context = "vehicle_retail_sale",
): readonly TaxGoldenCaseResult[] {
  return Object.freeze(
    cases.map((candidate, index): TaxGoldenCaseResult => {
      if (!isPlainRecord(candidate)) fail("invalid_input", `golden[${index}]`);
      exactKeys(
        candidate,
        [
          "case_id",
          "status",
          "description",
          "currency",
          "input",
          "expected",
          "rounding",
          "approval_required",
        ],
        [],
        `golden[${index}]`,
        "invalid_input",
      );
      if (
        typeof candidate.case_id !== "string" ||
        candidate.case_id.length < 1 ||
        candidate.case_id.length > 200 ||
        candidate.status !== "candidate" ||
        typeof candidate.description !== "string" ||
        candidate.description.trim().length < 1 ||
        candidate.description.length > 2_000 ||
        typeof candidate.currency !== "string" ||
        !isPlainRecord(candidate.input) ||
        !isPlainRecord(candidate.expected) ||
        !isPlainRecord(candidate.rounding) ||
        candidate.rounding.mode !== pack.definition.rules.rounding.mode ||
        candidate.rounding.scale !== pack.definition.rules.rounding.scale ||
        candidate.approval_required !== true
      ) {
        fail("invalid_input", `golden[${index}]`);
      }
      exactKeys(
        candidate.rounding,
        ["mode", "scale"],
        [],
        `golden[${index}].rounding`,
        "invalid_input",
      );
      const expectedKeys = [
        "eligible_taxable_consideration_minor",
        "non_taxable_fees_minor",
        ...pack.definition.rules.taxes.map((tax) => `${tax.key}_minor`),
        "total_tax_minor",
        "net_cash_consideration_before_payments_minor",
      ].sort();
      if (
        Object.keys(candidate.expected).sort().join(",") !==
        expectedKeys.join(",")
      ) {
        fail("invalid_input", `golden[${index}].expected`);
      }
      const snapshot = executeTaxCalculation(pack, {
        jurisdiction: pack.definition.jurisdiction,
        context,
        transactionDate: pack.definition.effective_from,
        currency: candidate.currency,
        input: candidate.input as TaxCalculationRequest["input"],
      });
      const mismatches: string[] = [];
      for (const key of Object.keys(candidate.expected).sort()) {
        const actual = snapshot.output[key];
        const expected = expectedValue(candidate.expected[key]);
        if (actual !== expected) mismatches.push(key);
      }
      return Object.freeze({
        caseId: candidate.case_id,
        passed: mismatches.length === 0,
        mismatches: Object.freeze(mismatches),
        snapshot,
      });
    }),
  );
}

export function createCalculationTaxPort(
  pack: CompiledTaxPack,
  options: Readonly<{
    jurisdiction: string;
    usage?: "preview" | "official";
  }>,
): CalculationTaxPort {
  return Object.freeze({
    calculate(
      request: Parameters<CalculationTaxPort["calculate"]>[0],
    ): TaxInvocationResult {
      const transactionDate = request.inputs.transaction_date;
      const currency = request.inputs.currency_code;
      if (typeof transactionDate !== "string" || typeof currency !== "string") {
        fail("invalid_input", "tax_port");
      }
      const selector: TaxPackSelector = {
        jurisdiction: options.jurisdiction,
        context: request.context,
        transactionDate,
        currency,
        usage: options.usage ?? "preview",
      };
      const selected = selectTaxPack([pack], selector);
      const inputs = { ...request.inputs } as Record<string, CalculationJson>;
      delete inputs.transaction_date;
      delete inputs.currency_code;
      const snapshot = executeTaxCalculation(selected, {
        jurisdiction: selector.jurisdiction,
        context: selector.context,
        transactionDate: selector.transactionDate,
        currency: selector.currency,
        input: inputs as TaxCalculationRequest["input"],
      });
      if (!CHECKSUM_PATTERN.test(snapshot.checksum))
        fail("invalid_input", "tax_port");
      return {
        outputs: snapshot.output,
        packKey: snapshot.packKey,
        packVersion: snapshot.packVersion,
        packChecksum: snapshot.packChecksum,
        snapshotChecksum: snapshot.checksum,
      };
    },
  });
}
