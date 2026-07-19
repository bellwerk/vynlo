import { describe, expect, it } from "vitest";

import {
  paymentCorrectableMinor,
  previewPaymentCorrectionRemainingMinor,
  type PaymentPreviewLedgerRow,
} from "./m3-payment-preview";

const original: PaymentPreviewLedgerRow = Object.freeze({
  amountMinor: "9007199254740991999",
  correctsTransactionId: null,
  paymentTransactionId: "payment-original",
  status: "settled",
});

const priorRefund: PaymentPreviewLedgerRow = Object.freeze({
  amountMinor: "-1000000000000000000",
  correctsTransactionId: original.paymentTransactionId,
  paymentTransactionId: "payment-prior-refund",
  status: "settled",
});

const unrelatedPayment: PaymentPreviewLedgerRow = Object.freeze({
  amountMinor: "50000",
  correctsTransactionId: null,
  paymentTransactionId: "payment-unrelated",
  status: "settled",
});

const ledger = Object.freeze([original, priorRefund, unrelatedPayment]);

describe("T-PAY-001 exact preview correction evidence", () => {
  it("subtracts a partial refund from the current ledger remainder exactly", () => {
    expect(paymentCorrectableMinor(original, ledger)).toBe(
      8007199254740991999n,
    );
    expect(
      previewPaymentCorrectionRemainingMinor({
        amountMinor: "2000000000000000000",
        correctionType: "refund",
        ledger,
        payment: original,
      }),
    ).toBe("6007199254740991999");
  });

  it("permits only an exact full reversal and never mutates the ledger", () => {
    const before = structuredClone(ledger);

    expect(
      previewPaymentCorrectionRemainingMinor({
        amountMinor: "8007199254740991999",
        correctionType: "reversal",
        ledger,
        payment: original,
      }),
    ).toBe("0");
    expect(
      previewPaymentCorrectionRemainingMinor({
        amountMinor: "1",
        correctionType: "reversal",
        ledger,
        payment: original,
      }),
    ).toBeNull();
    expect(ledger).toEqual(before);
  });

  it("rejects over-refunds and non-positive correction amounts", () => {
    expect(
      previewPaymentCorrectionRemainingMinor({
        amountMinor: "8007199254740992000",
        correctionType: "refund",
        ledger,
        payment: original,
      }),
    ).toBeNull();
    expect(
      previewPaymentCorrectionRemainingMinor({
        amountMinor: "0",
        correctionType: "refund",
        ledger,
        payment: original,
      }),
    ).toBeNull();
  });
});
