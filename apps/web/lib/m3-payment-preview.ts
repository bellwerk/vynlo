const positiveMinorUnitsPattern = /^[1-9][0-9]{0,18}$/u;

export interface PaymentPreviewLedgerRow {
  readonly amountMinor: string;
  readonly correctsTransactionId: string | null;
  readonly paymentTransactionId: string;
  readonly status: string;
}

export type PaymentPreviewCorrectionType = "refund" | "reversal";

export function paymentCorrectableMinor(
  payment: PaymentPreviewLedgerRow,
  ledger: readonly PaymentPreviewLedgerRow[],
): bigint {
  if (
    payment.status !== "settled" ||
    payment.correctsTransactionId !== null ||
    !positiveMinorUnitsPattern.test(payment.amountMinor)
  ) {
    return 0n;
  }

  const remaining = ledger.reduce(
    (total, row) =>
      row.correctsTransactionId === payment.paymentTransactionId
        ? total + BigInt(row.amountMinor)
        : total,
    BigInt(payment.amountMinor),
  );

  return remaining > 0n ? remaining : 0n;
}

export function previewPaymentCorrectionRemainingMinor(input: {
  readonly amountMinor: string;
  readonly correctionType: PaymentPreviewCorrectionType;
  readonly ledger: readonly PaymentPreviewLedgerRow[];
  readonly payment: PaymentPreviewLedgerRow;
}): string | null {
  if (!positiveMinorUnitsPattern.test(input.amountMinor)) return null;

  const correctableMinor = paymentCorrectableMinor(input.payment, input.ledger);
  const correctionMinor = BigInt(input.amountMinor);

  if (
    correctionMinor > correctableMinor ||
    (input.correctionType === "reversal" &&
      correctionMinor !== correctableMinor)
  ) {
    return null;
  }

  return (correctableMinor - correctionMinor).toString();
}
