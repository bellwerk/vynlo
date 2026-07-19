const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const KEY_PATTERN = /^[a-z][a-z0-9_.-]{0,127}$/u;
const CURRENCY_PATTERN = /^[A-Z]{3}$/u;
const MINOR_UNITS_PATTERN = /^(?:0|-?[1-9][0-9]{0,18})$/u;
const POSITIVE_DECIMAL_PATTERN = /^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$/u;
const NON_NEGATIVE_RATE_PATTERN = /^(?:0|[1-9][0-9]{0,2})(?:\.[0-9]{1,8})?$/u;
const RFC3339_INSTANT_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/u;
const POSTGRES_BIGINT_MIN = -9_223_372_036_854_775_808n;
const POSTGRES_BIGINT_MAX = 9_223_372_036_854_775_807n;

export const DEAL_LINE_ITEM_TYPES = [
  "vehicle",
  "fee",
  "discount",
  "accessory",
  "service",
  "other",
] as const;

export const FINANCE_APPLICATION_STATUSES = [
  "preparing",
  "submitted",
  "additional_information_required",
  "conditionally_approved",
  "approved",
  "declined",
  "customer_declined",
  "funded",
  "cancelled",
  "expired",
] as const;

export const RECORDABLE_PAYMENT_TYPES = [
  "deposit",
  "receipt",
  "balance_received",
  "lender_proceeds",
  "trade_in_credit",
  "other",
] as const;

export const PAYMENT_CORRECTION_TYPES = ["reversal", "refund"] as const;

export type FinanceApplicationStatus =
  (typeof FINANCE_APPLICATION_STATUSES)[number];
export type RecordablePaymentType = string;
export type PaymentCorrectionType = (typeof PAYMENT_CORRECTION_TYPES)[number];

export type M3DealDomainErrorCode =
  | "invalid_identifier"
  | "invalid_idempotency_key"
  | "invalid_expected_version"
  | "invalid_key"
  | "invalid_text"
  | "invalid_currency"
  | "invalid_money_minor"
  | "money_currency_mismatch"
  | "invalid_quantity"
  | "invalid_line_item"
  | "invalid_trade_in"
  | "invalid_finance_application"
  | "invalid_finance_transition"
  | "recurring_servicing_not_allowed"
  | "invalid_payment_type"
  | "invalid_payment_status"
  | "invalid_payment_correction"
  | "payment_over_correction"
  | "payment_version_conflict"
  | "reason_required";

export class M3DealDomainError extends Error {
  readonly code: M3DealDomainErrorCode;

  constructor(code: M3DealDomainErrorCode) {
    super(code);
    this.name = "M3DealDomainError";
    this.code = code;
  }
}

export interface M3Money {
  readonly amountMinor: string;
  readonly currencyCode: string;
}

function requireUuid(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new M3DealDomainError("invalid_identifier");
  }
  return value.toLowerCase();
}

function requireKey(value: unknown): string {
  if (typeof value !== "string") {
    throw new M3DealDomainError("invalid_key");
  }
  const normalized = value.trim().toLowerCase();
  if (!KEY_PATTERN.test(normalized)) {
    throw new M3DealDomainError("invalid_key");
  }
  return normalized;
}

function requireIdempotencyKey(value: unknown): string {
  if (typeof value !== "string") {
    throw new M3DealDomainError("invalid_idempotency_key");
  }
  const normalized = value.trim();
  if (normalized.length < 8 || normalized.length > 200) {
    throw new M3DealDomainError("invalid_idempotency_key");
  }
  return normalized;
}

function requireVersion(value: unknown): number {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < 1 ||
    (value as number) >= Number.MAX_SAFE_INTEGER
  ) {
    throw new M3DealDomainError("invalid_expected_version");
  }
  return value as number;
}

function normalizeText(
  value: unknown,
  maximumLength: number,
  nullable = false,
): string | null {
  if (value === null && nullable) {
    return null;
  }
  if (typeof value !== "string") {
    throw new M3DealDomainError("invalid_text");
  }
  const normalized = value.trim().replace(/\s+/gu, " ");
  if ((!normalized && !nullable) || normalized.length > maximumLength) {
    throw new M3DealDomainError("invalid_text");
  }
  return normalized || null;
}

function normalizeInstant(value: unknown): string {
  if (typeof value !== "string" || !RFC3339_INSTANT_PATTERN.test(value)) {
    throw new M3DealDomainError("invalid_text");
  }
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) {
    throw new M3DealDomainError("invalid_text");
  }
  return new Date(milliseconds).toISOString();
}

function parseMinorUnits(value: unknown): bigint {
  if (typeof value !== "string" || !MINOR_UNITS_PATTERN.test(value)) {
    throw new M3DealDomainError("invalid_money_minor");
  }
  const parsed = BigInt(value);
  if (parsed < POSTGRES_BIGINT_MIN || parsed > POSTGRES_BIGINT_MAX) {
    throw new M3DealDomainError("invalid_money_minor");
  }
  return parsed;
}

export function parseM3Money(
  value: Readonly<{ amountMinor: unknown; currencyCode: unknown }>,
): Readonly<M3Money> {
  const amountMinor = parseMinorUnits(value.amountMinor).toString();
  if (
    typeof value.currencyCode !== "string" ||
    !CURRENCY_PATTERN.test(value.currencyCode.trim().toUpperCase())
  ) {
    throw new M3DealDomainError("invalid_currency");
  }
  return Object.freeze({
    amountMinor,
    currencyCode: value.currencyCode.trim().toUpperCase(),
  });
}

function requirePositiveMoney(value: M3Money): void {
  if (BigInt(value.amountMinor) <= 0n) {
    throw new M3DealDomainError("invalid_money_minor");
  }
}

function requireSameCurrency(...values: readonly M3Money[]): string {
  const [first, ...rest] = values;
  if (
    !first ||
    rest.some((value) => value.currencyCode !== first.currencyCode)
  ) {
    throw new M3DealDomainError("money_currency_mismatch");
  }
  return first.currencyCode;
}

function assertPlainData(value: unknown): void {
  if (
    value === null ||
    ["string", "number", "boolean"].includes(typeof value)
  ) {
    return;
  }
  if (Array.isArray(value)) {
    for (const entry of value) assertPlainData(entry);
    return;
  }
  if (typeof value !== "object") {
    throw new M3DealDomainError("invalid_trade_in");
  }
  const prototype = Object.getPrototypeOf(value) as unknown;
  if (prototype !== Object.prototype && prototype !== null) {
    throw new M3DealDomainError("invalid_trade_in");
  }
  for (const [key, entry] of Object.entries(value)) {
    const normalizedKey = key.toLowerCase().replaceAll(/[^a-z0-9]/gu, "");
    if (
      [
        "command",
        "eval",
        "fetch",
        "filesystem",
        "function",
        "http",
        "import",
        "javascript",
        "module",
        "network",
        "script",
        "shell",
        "sql",
        "url",
      ].includes(normalizedKey)
    ) {
      throw new M3DealDomainError("invalid_trade_in");
    }
    assertPlainData(entry);
  }
}

export interface NormalizedDealLineItemCommand {
  readonly idempotencyKey: string;
  readonly dealId: string;
  readonly expectedVersion: number;
  readonly key: string;
  readonly itemType: (typeof DEAL_LINE_ITEM_TYPES)[number];
  readonly label: string;
  readonly quantity: string;
  readonly unitAmount: M3Money;
  readonly taxClassificationKey: string | null;
  readonly paymentTimingKey: string | null;
  readonly sortOrder: number;
  readonly sourceKey: string | null;
  readonly sourceReference: string | null;
}

export function normalizeDealLineItemCommand(input: {
  readonly idempotencyKey: unknown;
  readonly dealId: unknown;
  readonly expectedVersion: unknown;
  readonly key: unknown;
  readonly itemType: unknown;
  readonly label: unknown;
  readonly quantity: unknown;
  readonly unitAmount: Readonly<{
    amountMinor: unknown;
    currencyCode: unknown;
  }>;
  readonly dealCurrencyCode: unknown;
  readonly taxClassificationKey?: unknown;
  readonly paymentTimingKey?: unknown;
  readonly sortOrder: unknown;
  readonly sourceKey?: unknown;
  readonly sourceReference?: unknown;
}): Readonly<NormalizedDealLineItemCommand> {
  if (
    typeof input.itemType !== "string" ||
    !DEAL_LINE_ITEM_TYPES.includes(
      input.itemType as (typeof DEAL_LINE_ITEM_TYPES)[number],
    )
  ) {
    throw new M3DealDomainError("invalid_line_item");
  }
  if (
    typeof input.quantity !== "string" ||
    !POSITIVE_DECIMAL_PATTERN.test(input.quantity) ||
    Number(input.quantity) <= 0
  ) {
    throw new M3DealDomainError("invalid_quantity");
  }
  if (
    !Number.isSafeInteger(input.sortOrder) ||
    (input.sortOrder as number) < 0
  ) {
    throw new M3DealDomainError("invalid_line_item");
  }
  const unitAmount = parseM3Money(input.unitAmount);
  const dealCurrency = parseM3Money({
    amountMinor: "0",
    currencyCode: input.dealCurrencyCode,
  });
  requireSameCurrency(unitAmount, dealCurrency);

  return Object.freeze({
    idempotencyKey: requireIdempotencyKey(input.idempotencyKey),
    dealId: requireUuid(input.dealId),
    expectedVersion: requireVersion(input.expectedVersion),
    key: requireKey(input.key),
    itemType: input.itemType as (typeof DEAL_LINE_ITEM_TYPES)[number],
    label: normalizeText(input.label, 200)!,
    quantity: input.quantity,
    unitAmount,
    taxClassificationKey:
      input.taxClassificationKey === null ||
      input.taxClassificationKey === undefined
        ? null
        : requireKey(input.taxClassificationKey),
    paymentTimingKey:
      input.paymentTimingKey === null || input.paymentTimingKey === undefined
        ? null
        : requireKey(input.paymentTimingKey),
    sortOrder: input.sortOrder as number,
    sourceKey:
      input.sourceKey === null || input.sourceKey === undefined
        ? null
        : requireKey(input.sourceKey),
    sourceReference: normalizeText(input.sourceReference ?? null, 500, true),
  });
}

export interface NormalizedTradeInCommand {
  readonly dealId: string;
  readonly ownerPartyId: string;
  readonly vehicleId: string | null;
  readonly enteredVehicleFacts: Readonly<Record<string, unknown>> | null;
  readonly allowance: M3Money;
  readonly lienAmount: M3Money;
  readonly payoffAmount: M3Money;
  readonly lenderPartyId: string | null;
  readonly odometerValue: number | null;
  readonly odometerUnit: "km" | "mi" | null;
  readonly conditionKey: string | null;
  readonly taxEligibilityInputs: Readonly<Record<string, unknown>>;
}

export type NormalizedTradeInDetails = Omit<NormalizedTradeInCommand, "dealId">;

export interface TradeInDetailsInput {
  readonly ownerPartyId: unknown;
  readonly vehicleId: unknown;
  readonly enteredVehicleFacts: unknown;
  readonly allowance: Readonly<{ amountMinor: unknown; currencyCode: unknown }>;
  readonly lienAmount: Readonly<{
    amountMinor: unknown;
    currencyCode: unknown;
  }>;
  readonly payoffAmount: Readonly<{
    amountMinor: unknown;
    currencyCode: unknown;
  }>;
  readonly lenderPartyId: unknown;
  readonly odometerValue: unknown;
  readonly odometerUnit: unknown;
  readonly conditionKey: unknown;
  readonly taxEligibilityInputs: unknown;
}

export function normalizeTradeInDetails(
  input: TradeInDetailsInput,
): Readonly<NormalizedTradeInDetails> {
  const vehicleId =
    input.vehicleId === null ? null : requireUuid(input.vehicleId);
  if (
    input.enteredVehicleFacts !== null &&
    (typeof input.enteredVehicleFacts !== "object" ||
      Array.isArray(input.enteredVehicleFacts))
  ) {
    throw new M3DealDomainError("invalid_trade_in");
  }
  if (vehicleId === null && input.enteredVehicleFacts === null) {
    throw new M3DealDomainError("invalid_trade_in");
  }
  assertPlainData(input.enteredVehicleFacts);
  assertPlainData(input.taxEligibilityInputs);
  if (
    typeof input.taxEligibilityInputs !== "object" ||
    input.taxEligibilityInputs === null ||
    Array.isArray(input.taxEligibilityInputs)
  ) {
    throw new M3DealDomainError("invalid_trade_in");
  }
  const allowance = parseM3Money(input.allowance);
  const lienAmount = parseM3Money(input.lienAmount);
  const payoffAmount = parseM3Money(input.payoffAmount);
  requireSameCurrency(allowance, lienAmount, payoffAmount);
  if (
    [allowance, lienAmount, payoffAmount].some(
      (money) => BigInt(money.amountMinor) < 0n,
    )
  ) {
    throw new M3DealDomainError("invalid_trade_in");
  }
  const hasOdometer =
    input.odometerValue !== null || input.odometerUnit !== null;
  if (
    hasOdometer &&
    (!Number.isSafeInteger(input.odometerValue) ||
      (input.odometerValue as number) < 0 ||
      !["km", "mi"].includes(input.odometerUnit as string))
  ) {
    throw new M3DealDomainError("invalid_trade_in");
  }

  return Object.freeze({
    ownerPartyId: requireUuid(input.ownerPartyId),
    vehicleId,
    enteredVehicleFacts:
      input.enteredVehicleFacts === null
        ? null
        : Object.freeze({
            ...(input.enteredVehicleFacts as Record<string, unknown>),
          }),
    allowance,
    lienAmount,
    payoffAmount,
    lenderPartyId:
      input.lenderPartyId === null ? null : requireUuid(input.lenderPartyId),
    odometerValue: hasOdometer ? (input.odometerValue as number) : null,
    odometerUnit: hasOdometer ? (input.odometerUnit as "km" | "mi") : null,
    conditionKey:
      input.conditionKey === null ? null : requireKey(input.conditionKey),
    taxEligibilityInputs: Object.freeze({
      ...(input.taxEligibilityInputs as Record<string, unknown>),
    }),
  });
}

export function normalizeTradeInCommand(
  input: TradeInDetailsInput & { readonly dealId: unknown },
): Readonly<NormalizedTradeInCommand> {
  return Object.freeze({
    dealId: requireUuid(input.dealId),
    ...normalizeTradeInDetails(input),
  });
}

const PROHIBITED_SERVICING_KEYS = new Set([
  "amortization",
  "aprpayment",
  "collection",
  "installment",
  "latefee",
  "paymentfrequency",
  "paymentschedule",
  "principalallocation",
  "repaymentschedule",
  "repossession",
  "servicing",
]);

function assertNoServicingData(value: unknown): void {
  if (
    value === null ||
    ["string", "number", "boolean"].includes(typeof value)
  ) {
    return;
  }
  if (Array.isArray(value)) {
    for (const entry of value) assertNoServicingData(entry);
    return;
  }
  if (typeof value !== "object") {
    throw new M3DealDomainError("invalid_finance_application");
  }
  for (const [key, entry] of Object.entries(value)) {
    const normalized = key.toLowerCase().replaceAll(/[^a-z0-9]/gu, "");
    if (PROHIBITED_SERVICING_KEYS.has(normalized)) {
      throw new M3DealDomainError("recurring_servicing_not_allowed");
    }
    assertNoServicingData(entry);
  }
}

export interface NormalizedFinanceApplicationCommand {
  readonly idempotencyKey: string;
  readonly dealId: string;
  readonly applicantPartyId: string;
  readonly lenderPartyId: string;
  readonly requestedAmount: M3Money;
  readonly externalReference: string | null;
  readonly lenderReportedAnnualRate: string | null;
  readonly lenderReportedTermMonths: number | null;
  readonly notes: string | null;
}

export function normalizeFinanceApplicationCommand(input: {
  readonly idempotencyKey: unknown;
  readonly dealId: unknown;
  readonly applicantPartyId: unknown;
  readonly lenderPartyId: unknown;
  readonly requestedAmount: Readonly<{
    amountMinor: unknown;
    currencyCode: unknown;
  }>;
  readonly externalReference: unknown;
  readonly lenderReportedAnnualRate: unknown;
  readonly lenderReportedTermMonths: unknown;
  readonly notes: unknown;
  readonly extra?: unknown;
}): Readonly<NormalizedFinanceApplicationCommand> {
  assertNoServicingData(input);
  const requestedAmount = parseM3Money(input.requestedAmount);
  requirePositiveMoney(requestedAmount);
  let lenderReportedAnnualRate: string | null = null;
  if (input.lenderReportedAnnualRate !== null) {
    if (
      typeof input.lenderReportedAnnualRate !== "string" ||
      !NON_NEGATIVE_RATE_PATTERN.test(input.lenderReportedAnnualRate)
    ) {
      throw new M3DealDomainError("invalid_finance_application");
    }
    lenderReportedAnnualRate = input.lenderReportedAnnualRate;
  }
  if (
    input.lenderReportedTermMonths !== null &&
    (!Number.isSafeInteger(input.lenderReportedTermMonths) ||
      (input.lenderReportedTermMonths as number) < 1 ||
      (input.lenderReportedTermMonths as number) > 1_200)
  ) {
    throw new M3DealDomainError("invalid_finance_application");
  }
  return Object.freeze({
    idempotencyKey: requireIdempotencyKey(input.idempotencyKey),
    dealId: requireUuid(input.dealId),
    applicantPartyId: requireUuid(input.applicantPartyId),
    lenderPartyId: requireUuid(input.lenderPartyId),
    requestedAmount,
    externalReference: normalizeText(input.externalReference, 500, true),
    lenderReportedAnnualRate,
    lenderReportedTermMonths: input.lenderReportedTermMonths as number | null,
    notes: normalizeText(input.notes, 4_000, true),
  });
}

const FINANCE_TRANSITIONS: Readonly<
  Record<FinanceApplicationStatus, readonly FinanceApplicationStatus[]>
> = {
  preparing: ["submitted", "cancelled"],
  submitted: [
    "additional_information_required",
    "conditionally_approved",
    "approved",
    "declined",
    "cancelled",
  ],
  additional_information_required: [
    "submitted",
    "conditionally_approved",
    "approved",
    "declined",
    "cancelled",
  ],
  conditionally_approved: [
    "approved",
    "funded",
    "customer_declined",
    "expired",
    "cancelled",
  ],
  approved: ["funded", "customer_declined", "expired", "cancelled"],
  declined: [],
  customer_declined: [],
  funded: [],
  cancelled: [],
  expired: [],
};

export function planFinanceApplicationTransition(input: {
  readonly currentStatus: unknown;
  readonly targetStatus: unknown;
  readonly expectedVersion: unknown;
  readonly currentVersion: unknown;
  readonly reason: unknown;
  readonly allRequiredConditionsSatisfied: boolean;
}): Readonly<{
  readonly fromStatus: FinanceApplicationStatus;
  readonly toStatus: FinanceApplicationStatus;
  readonly resultingVersion: number;
  readonly reason: string | null;
}> {
  if (
    typeof input.currentStatus !== "string" ||
    typeof input.targetStatus !== "string" ||
    !FINANCE_APPLICATION_STATUSES.includes(
      input.currentStatus as FinanceApplicationStatus,
    ) ||
    !FINANCE_APPLICATION_STATUSES.includes(
      input.targetStatus as FinanceApplicationStatus,
    )
  ) {
    throw new M3DealDomainError("invalid_finance_transition");
  }
  const expectedVersion = requireVersion(input.expectedVersion);
  const currentVersion = requireVersion(input.currentVersion);
  if (expectedVersion !== currentVersion) {
    throw new M3DealDomainError("payment_version_conflict");
  }
  const currentStatus = input.currentStatus as FinanceApplicationStatus;
  const targetStatus = input.targetStatus as FinanceApplicationStatus;
  if (!FINANCE_TRANSITIONS[currentStatus].includes(targetStatus)) {
    throw new M3DealDomainError("invalid_finance_transition");
  }
  if (
    ["approved", "funded"].includes(targetStatus) &&
    !input.allRequiredConditionsSatisfied
  ) {
    throw new M3DealDomainError("invalid_finance_transition");
  }
  const reasonRequired = [
    "declined",
    "customer_declined",
    "cancelled",
  ].includes(targetStatus);
  const reason = normalizeText(input.reason, 2_000, true);
  if (reasonRequired && reason === null) {
    throw new M3DealDomainError("reason_required");
  }
  return Object.freeze({
    fromStatus: currentStatus,
    toStatus: targetStatus,
    resultingVersion: currentVersion + 1,
    reason,
  });
}

export interface PaymentTransactionSnapshot {
  readonly id: string;
  readonly type: RecordablePaymentType | PaymentCorrectionType;
  readonly status: "recorded" | "settled" | "cancelled";
  readonly money: M3Money;
  readonly version: number;
  readonly correctsTransactionId: string | null;
}

export function normalizePaymentRecordCommand(input: {
  readonly idempotencyKey: unknown;
  readonly dealId: unknown;
  readonly type: unknown;
  readonly money: Readonly<{ amountMinor: unknown; currencyCode: unknown }>;
  readonly dealCurrencyCode: unknown;
  readonly methodKey: unknown;
  readonly reference: unknown;
  readonly occurredAt: unknown;
  readonly proofFileId: unknown;
  readonly notes: unknown;
}): Readonly<{
  readonly idempotencyKey: string;
  readonly dealId: string;
  readonly type: RecordablePaymentType;
  readonly money: M3Money;
  readonly methodKey: string;
  readonly reference: string | null;
  readonly occurredAt: string;
  readonly proofFileId: string | null;
  readonly notes: string | null;
}> {
  const type = requireKey(input.type);
  if (PAYMENT_CORRECTION_TYPES.includes(type as PaymentCorrectionType)) {
    throw new M3DealDomainError("invalid_payment_type");
  }
  const money = parseM3Money(input.money);
  requirePositiveMoney(money);
  requireSameCurrency(
    money,
    parseM3Money({ amountMinor: "0", currencyCode: input.dealCurrencyCode }),
  );
  return Object.freeze({
    idempotencyKey: requireIdempotencyKey(input.idempotencyKey),
    dealId: requireUuid(input.dealId),
    type,
    money,
    methodKey: requireKey(input.methodKey),
    reference: normalizeText(input.reference, 500, true),
    occurredAt: normalizeInstant(input.occurredAt),
    proofFileId:
      input.proofFileId === null ? null : requireUuid(input.proofFileId),
    notes: normalizeText(input.notes, 4_000, true),
  });
}

export function planPaymentSettlement(input: {
  readonly transaction: PaymentTransactionSnapshot;
  readonly expectedVersion: unknown;
  readonly settledAt: unknown;
}): Readonly<{
  readonly transactionId: string;
  readonly resultingVersion: number;
  readonly settledAt: string;
}> {
  const expectedVersion = requireVersion(input.expectedVersion);
  if (input.transaction.version !== expectedVersion) {
    throw new M3DealDomainError("payment_version_conflict");
  }
  if (
    input.transaction.status !== "recorded" ||
    PAYMENT_CORRECTION_TYPES.includes(
      input.transaction.type as PaymentCorrectionType,
    )
  ) {
    throw new M3DealDomainError("invalid_payment_status");
  }
  requirePositiveMoney(input.transaction.money);
  return Object.freeze({
    transactionId: requireUuid(input.transaction.id),
    resultingVersion: expectedVersion + 1,
    settledAt: normalizeInstant(input.settledAt),
  });
}

export function planPaymentCorrection(input: {
  readonly idempotencyKey: unknown;
  readonly original: PaymentTransactionSnapshot;
  readonly expectedVersion: unknown;
  readonly previousCorrections: readonly PaymentTransactionSnapshot[];
  readonly correctionType: unknown;
  readonly requestedAmount: Readonly<{
    amountMinor: unknown;
    currencyCode: unknown;
  }>;
  readonly reason: unknown;
}): Readonly<{
  readonly idempotencyKey: string;
  readonly originalTransactionId: string;
  readonly correctionType: PaymentCorrectionType;
  readonly money: M3Money;
  readonly remainingAfterMinor: string;
  readonly reason: string;
}> {
  const expectedVersion = requireVersion(input.expectedVersion);
  if (input.original.version !== expectedVersion) {
    throw new M3DealDomainError("payment_version_conflict");
  }
  if (
    input.original.status !== "settled" ||
    PAYMENT_CORRECTION_TYPES.includes(
      input.original.type as PaymentCorrectionType,
    ) ||
    input.original.correctsTransactionId !== null
  ) {
    throw new M3DealDomainError("invalid_payment_correction");
  }
  requirePositiveMoney(input.original.money);
  if (
    typeof input.correctionType !== "string" ||
    !PAYMENT_CORRECTION_TYPES.includes(
      input.correctionType as PaymentCorrectionType,
    )
  ) {
    throw new M3DealDomainError("invalid_payment_type");
  }
  const requestedAmount = parseM3Money(input.requestedAmount);
  requirePositiveMoney(requestedAmount);
  requireSameCurrency(input.original.money, requestedAmount);
  let correctedMinor = 0n;
  for (const correction of input.previousCorrections) {
    if (
      correction.status !== "settled" ||
      !PAYMENT_CORRECTION_TYPES.includes(
        correction.type as PaymentCorrectionType,
      ) ||
      correction.correctsTransactionId !== input.original.id ||
      correction.money.currencyCode !== input.original.money.currencyCode ||
      BigInt(correction.money.amountMinor) >= 0n
    ) {
      throw new M3DealDomainError("invalid_payment_correction");
    }
    correctedMinor += -BigInt(correction.money.amountMinor);
  }
  const originalMinor = BigInt(input.original.money.amountMinor);
  const remainingMinor = originalMinor - correctedMinor;
  const requestedMinor = BigInt(requestedAmount.amountMinor);
  if (remainingMinor <= 0n || requestedMinor > remainingMinor) {
    throw new M3DealDomainError("payment_over_correction");
  }
  if (
    input.correctionType === "reversal" &&
    requestedMinor !== remainingMinor
  ) {
    throw new M3DealDomainError("invalid_payment_correction");
  }
  const reason = normalizeText(input.reason, 2_000, true);
  if (reason === null) {
    throw new M3DealDomainError("reason_required");
  }
  return Object.freeze({
    idempotencyKey: requireIdempotencyKey(input.idempotencyKey),
    originalTransactionId: requireUuid(input.original.id),
    correctionType: input.correctionType as PaymentCorrectionType,
    money: Object.freeze({
      amountMinor: (-requestedMinor).toString(),
      currencyCode: input.original.money.currencyCode,
    }),
    remainingAfterMinor: (remainingMinor - requestedMinor).toString(),
    reason,
  });
}
