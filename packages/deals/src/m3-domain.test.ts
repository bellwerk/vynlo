import { describe, expect, it } from "vitest";

import {
  M3DealDomainError,
  normalizeDealLineItemCommand,
  normalizeFinanceApplicationCommand,
  normalizePaymentRecordCommand,
  normalizeTradeInCommand,
  parseM3Money,
  planFinanceApplicationTransition,
  planPaymentCorrection,
  planPaymentSettlement,
  type PaymentTransactionSnapshot,
} from "./m3-domain";

const DEAL_ID = "10000000-0000-4000-8000-000000000001";
const PARTY_ID = "20000000-0000-4000-8000-000000000001";
const LENDER_ID = "20000000-0000-4000-8000-000000000002";
const VEHICLE_ID = "30000000-0000-4000-8000-000000000001";
const FILE_ID = "40000000-0000-4000-8000-000000000001";
const TRANSACTION_ID = "50000000-0000-4000-8000-000000000001";

function expectCode(operation: () => unknown, code: string): void {
  expect(operation).toThrowError(M3DealDomainError);
  try {
    operation();
  } catch (error) {
    expect(error).toMatchObject({ code });
  }
}

describe("M3-DEAL-AC-002 / T-DEAL-001 exact deal values", () => {
  it("preserves the full PostgreSQL bigint range as canonical strings", () => {
    expect(
      parseM3Money({
        amountMinor: "9223372036854775807",
        currencyCode: "cad",
      }),
    ).toEqual({ amountMinor: "9223372036854775807", currencyCode: "CAD" });
    expect(
      parseM3Money({
        amountMinor: "-9223372036854775808",
        currencyCode: "CAD",
      }),
    ).toEqual({ amountMinor: "-9223372036854775808", currencyCode: "CAD" });

    for (const amountMinor of [
      10,
      "01",
      "-0",
      "+1",
      "9223372036854775808",
      "-9223372036854775809",
    ]) {
      expectCode(
        () => parseM3Money({ amountMinor, currencyCode: "CAD" }),
        "invalid_money_minor",
      );
    }
  });

  it("normalizes an exact line item and rejects cross-currency input", () => {
    const command = normalizeDealLineItemCommand({
      idempotencyKey: "line-item-001",
      dealId: DEAL_ID,
      expectedVersion: 4,
      key: "vehicle.price",
      itemType: "vehicle",
      label: "  Vehicle   price ",
      quantity: "1.000000",
      unitAmount: { amountMinor: "2499999", currencyCode: "CAD" },
      dealCurrencyCode: "CAD",
      taxClassificationKey: "vehicle.sale",
      paymentTimingKey: "delivery",
      sortOrder: 10,
      sourceKey: "operator",
      sourceReference: null,
    });

    expect(command).toMatchObject({
      dealId: DEAL_ID,
      label: "Vehicle price",
      quantity: "1.000000",
      unitAmount: { amountMinor: "2499999", currencyCode: "CAD" },
    });
    expect(Object.isFrozen(command)).toBe(true);

    expectCode(
      () =>
        normalizeDealLineItemCommand({
          ...command,
          unitAmount: { amountMinor: "1", currencyCode: "USD" },
          dealCurrencyCode: "CAD",
          taxClassificationKey: null,
          paymentTimingKey: null,
          sourceKey: null,
          sourceReference: null,
        }),
      "money_currency_mismatch",
    );
  });
});

describe("M3-DEAL-AC-003 / T-DEAL-002 trade-in boundaries", () => {
  it("keeps allowance, lien, and payoff distinct and does not create inventory", () => {
    const tradeIn = normalizeTradeInCommand({
      dealId: DEAL_ID,
      ownerPartyId: PARTY_ID,
      vehicleId: VEHICLE_ID,
      enteredVehicleFacts: null,
      allowance: { amountMinor: "800000", currencyCode: "CAD" },
      lienAmount: { amountMinor: "500000", currencyCode: "CAD" },
      payoffAmount: { amountMinor: "510000", currencyCode: "CAD" },
      lenderPartyId: LENDER_ID,
      odometerValue: 87_000,
      odometerUnit: "km",
      conditionKey: "used.good",
      taxEligibilityInputs: { acquiredFromBuyer: true },
    });

    expect(tradeIn).toMatchObject({
      allowance: { amountMinor: "800000" },
      lienAmount: { amountMinor: "500000" },
      payoffAmount: { amountMinor: "510000" },
    });
    expect(tradeIn).not.toHaveProperty("resultingInventoryUnitId");
  });

  it("requires vehicle identity and rejects executable tax input", () => {
    expectCode(
      () =>
        normalizeTradeInCommand({
          dealId: DEAL_ID,
          ownerPartyId: PARTY_ID,
          vehicleId: null,
          enteredVehicleFacts: null,
          allowance: { amountMinor: "1", currencyCode: "CAD" },
          lienAmount: { amountMinor: "0", currencyCode: "CAD" },
          payoffAmount: { amountMinor: "0", currencyCode: "CAD" },
          lenderPartyId: null,
          odometerValue: null,
          odometerUnit: null,
          conditionKey: null,
          taxEligibilityInputs: {},
        }),
      "invalid_trade_in",
    );
    expectCode(
      () =>
        normalizeTradeInCommand({
          dealId: DEAL_ID,
          ownerPartyId: PARTY_ID,
          vehicleId: VEHICLE_ID,
          enteredVehicleFacts: null,
          allowance: { amountMinor: "1", currencyCode: "CAD" },
          lienAmount: { amountMinor: "0", currencyCode: "CAD" },
          payoffAmount: { amountMinor: "0", currencyCode: "CAD" },
          lenderPartyId: null,
          odometerValue: null,
          odometerUnit: null,
          conditionKey: null,
          taxEligibilityInputs: { sql: "select 1" },
        }),
      "invalid_trade_in",
    );
  });
});

describe("M3-FIN-AC-001 / T-FIN-001 external-lender tracking", () => {
  it("accepts lender-reported terms without creating servicing data", () => {
    const command = normalizeFinanceApplicationCommand({
      idempotencyKey: "finance-application-001",
      dealId: DEAL_ID,
      applicantPartyId: PARTY_ID,
      lenderPartyId: LENDER_ID,
      requestedAmount: { amountMinor: "2000000", currencyCode: "CAD" },
      externalReference: "LENDER-REF-1",
      lenderReportedAnnualRate: "8.125",
      lenderReportedTermMonths: 60,
      notes: null,
    });
    expect(command).toMatchObject({
      lenderReportedAnnualRate: "8.125",
      lenderReportedTermMonths: 60,
    });
    expect(command).not.toHaveProperty("paymentSchedule");
  });

  it("rejects recurring-servicing fields at any depth", () => {
    expectCode(
      () =>
        normalizeFinanceApplicationCommand({
          idempotencyKey: "finance-application-001",
          dealId: DEAL_ID,
          applicantPartyId: PARTY_ID,
          lenderPartyId: LENDER_ID,
          requestedAmount: { amountMinor: "2000000", currencyCode: "CAD" },
          externalReference: null,
          lenderReportedAnnualRate: null,
          lenderReportedTermMonths: null,
          notes: null,
          extra: { paymentSchedule: [{ due: "2027-01-01" }] },
        }),
      "recurring_servicing_not_allowed",
    );
  });

  it("enforces condition and reason guards on lifecycle transitions", () => {
    expectCode(
      () =>
        planFinanceApplicationTransition({
          currentStatus: "submitted",
          targetStatus: "approved",
          expectedVersion: 2,
          currentVersion: 2,
          reason: null,
          allRequiredConditionsSatisfied: false,
        }),
      "invalid_finance_transition",
    );
    expectCode(
      () =>
        planFinanceApplicationTransition({
          currentStatus: "submitted",
          targetStatus: "declined",
          expectedVersion: 2,
          currentVersion: 2,
          reason: " ",
          allRequiredConditionsSatisfied: true,
        }),
      "reason_required",
    );
    expect(
      planFinanceApplicationTransition({
        currentStatus: "submitted",
        targetStatus: "conditionally_approved",
        expectedVersion: 2,
        currentVersion: 2,
        reason: null,
        allRequiredConditionsSatisfied: true,
      }),
    ).toMatchObject({
      resultingVersion: 3,
      toStatus: "conditionally_approved",
    });
  });
});

describe("M3-PAY-AC-001..003 / T-PAY-001..003 one-time money", () => {
  const original: PaymentTransactionSnapshot = {
    id: TRANSACTION_ID,
    type: "deposit",
    status: "settled",
    money: { amountMinor: "100000", currencyCode: "CAD" },
    version: 2,
    correctsTransactionId: null,
  };

  it("records only positive one-time events and settles by expected version", () => {
    const record = normalizePaymentRecordCommand({
      idempotencyKey: "payment-record-001",
      dealId: DEAL_ID,
      type: "deposit",
      money: { amountMinor: "100000", currencyCode: "CAD" },
      dealCurrencyCode: "CAD",
      methodKey: "bank_transfer",
      reference: "SYNTHETIC-REF",
      occurredAt: "2026-07-16T12:00:00-04:00",
      proofFileId: FILE_ID,
      notes: null,
    });
    expect(record.occurredAt).toBe("2026-07-16T16:00:00.000Z");
    expect(
      normalizePaymentRecordCommand({
        ...record,
        dealCurrencyCode: "CAD",
        type: "configured.credit",
      }),
    ).toMatchObject({ type: "configured.credit" });

    expect(
      planPaymentSettlement({
        transaction: { ...original, status: "recorded", version: 1 },
        expectedVersion: 1,
        settledAt: "2026-07-16T17:00:00Z",
      }),
    ).toEqual({
      transactionId: TRANSACTION_ID,
      resultingVersion: 2,
      settledAt: "2026-07-16T17:00:00.000Z",
    });

    for (const type of ["refund", "reversal"]) {
      expectCode(
        () =>
          normalizePaymentRecordCommand({
            ...record,
            type,
            money: { amountMinor: "1", currencyCode: "CAD" },
            dealCurrencyCode: "CAD",
            occurredAt: "2026-07-16T17:00:00Z",
          }),
        "invalid_payment_type",
      );
    }
  });

  it("creates negative linked refunds while preserving the original", () => {
    const refund = planPaymentCorrection({
      idempotencyKey: "payment-refund-001",
      original,
      expectedVersion: 2,
      previousCorrections: [],
      correctionType: "refund",
      requestedAmount: { amountMinor: "25000", currencyCode: "CAD" },
      reason: "Customer-requested partial refund",
    });
    expect(refund).toEqual({
      idempotencyKey: "payment-refund-001",
      originalTransactionId: TRANSACTION_ID,
      correctionType: "refund",
      money: { amountMinor: "-25000", currencyCode: "CAD" },
      remainingAfterMinor: "75000",
      reason: "Customer-requested partial refund",
    });
    expect(original.money.amountMinor).toBe("100000");
    expectCode(
      () =>
        planPaymentCorrection({
          idempotencyKey: "payment-refund-stale",
          original,
          expectedVersion: 1,
          previousCorrections: [],
          correctionType: "refund",
          requestedAmount: { amountMinor: "1", currencyCode: "CAD" },
          reason: "Stale synthetic correction",
        }),
      "payment_version_conflict",
    );
  });

  it("caps aggregate corrections and makes reversal consume the exact remainder", () => {
    const priorRefund: PaymentTransactionSnapshot = {
      id: "50000000-0000-4000-8000-000000000002",
      type: "refund",
      status: "settled",
      money: { amountMinor: "-25000", currencyCode: "CAD" },
      version: 1,
      correctsTransactionId: TRANSACTION_ID,
    };
    expect(
      planPaymentCorrection({
        idempotencyKey: "payment-reversal-001",
        original,
        expectedVersion: 2,
        previousCorrections: [priorRefund],
        correctionType: "reversal",
        requestedAmount: { amountMinor: "75000", currencyCode: "CAD" },
        reason: "Reverse remaining settlement",
      }),
    ).toMatchObject({
      money: { amountMinor: "-75000" },
      remainingAfterMinor: "0",
    });

    expectCode(
      () =>
        planPaymentCorrection({
          idempotencyKey: "payment-refund-over",
          original,
          expectedVersion: 2,
          previousCorrections: [priorRefund],
          correctionType: "refund",
          requestedAmount: { amountMinor: "75001", currencyCode: "CAD" },
          reason: "Invalid over-refund",
        }),
      "payment_over_correction",
    );
    expectCode(
      () =>
        planPaymentCorrection({
          idempotencyKey: "payment-reversal-partial",
          original,
          expectedVersion: 2,
          previousCorrections: [priorRefund],
          correctionType: "reversal",
          requestedAmount: { amountMinor: "1", currencyCode: "CAD" },
          reason: "Invalid partial reversal",
        }),
      "invalid_payment_correction",
    );
  });
});
