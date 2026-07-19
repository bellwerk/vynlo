import { describe, expect, it, vi } from "vitest";

import type { AuthenticatedRpcGateway } from "./vertical-slice-api";
import {
  M3ApplicationValidationError,
  M3FinancePaymentsApplicationService,
  M3RpcContractError,
} from "./index";

const WORKSPACE_ID = "10000000-0000-4000-8000-000000000001";
const DEAL_ID = "20000000-0000-4000-8000-000000000001";
const APPLICANT_ID = "30000000-0000-4000-8000-000000000001";
const LENDER_ID = "40000000-0000-4000-8000-000000000001";
const FINANCE_ID = "50000000-0000-4000-8000-000000000001";
const PAYMENT_ID = "60000000-0000-4000-8000-000000000001";
const CORRECTION_ID = "70000000-0000-4000-8000-000000000001";
const ACTOR_ID = "71000000-0000-4000-8000-000000000001";
const AUDIT_ID = "80000000-0000-4000-8000-000000000001";
const OUTBOX_ID = "90000000-0000-4000-8000-000000000001";
const FILE_ID = "90000000-0000-4000-8000-000000000002";

function command(body: unknown) {
  return {
    body,
    metadata: {
      accessToken: "header.payload.signature",
      correlationId: "a0000000-0000-4000-8000-000000000001",
      idempotencyKey: "m3-money-command-0001",
      requestId: "m3-money-request-0001",
      workspaceId: WORKSPACE_ID,
    },
  };
}

function entityCommand(body: unknown, entityId: string) {
  return { ...command(body), entityId };
}

function evidence(extra: Record<string, unknown>) {
  return [
    {
      aggregate_version: 2,
      audit_event_id: AUDIT_ID,
      outbox_event_id: OUTBOX_ID,
      replayed: false,
      ...extra,
    },
  ];
}

function service(result: unknown) {
  const gateway: AuthenticatedRpcGateway = {
    invoke: vi.fn(async () => result),
  };
  return {
    application: new M3FinancePaymentsApplicationService(gateway),
    gateway,
  };
}

describe("T-FIN-001 / T-API-001 external finance contracts", () => {
  it("reads exact lender detail and bounded conditions without provider payloads", async () => {
    const timestamp = "2026-07-16T12:00:00Z";
    const { application, gateway } = service([
      {
        applicant_party_id: APPLICANT_ID,
        approval_expires_at: null,
        approved_amount_minor: null,
        conditions: [
          {
            condition_id: CORRECTION_ID,
            condition_key: "income_verification",
            created_at: timestamp,
            description: "Synthetic income verification",
            due_at: "2026-07-30T12:00:00Z",
            logical_condition_id: CORRECTION_ID,
            replaces_condition_id: null,
            required: true,
            satisfied_at: null,
            status: "active",
            supporting_file_id: FILE_ID,
            version: 1,
          },
        ],
        created_at: timestamp,
        currency_code: "CAD",
        customer_accepted_at: null,
        deal_id: DEAL_ID,
        decision_at: null,
        external_reference: "SYNTHETIC-EXT",
        finance_application_id: FINANCE_ID,
        funded_at: null,
        funding_reference: null,
        lender_party_id: LENDER_ID,
        lender_reported_annual_rate: "6.125",
        lender_reported_term_months: 60,
        notes: null,
        requested_amount_minor: "3250000",
        status: "submitted",
        status_reason: null,
        submitted_at: timestamp,
        updated_at: timestamp,
        version: 2,
      },
    ]);

    await expect(
      application.getFinanceApplication({
        accessToken: "header.payload.signature",
        financeApplicationId: FINANCE_ID,
        workspaceId: WORKSPACE_ID,
      }),
    ).resolves.toMatchObject({
      conditions: [
        {
          conditionKey: "income_verification",
          dueAt: "2026-07-30T12:00:00Z",
          logicalConditionId: CORRECTION_ID,
          supportingFileId: FILE_ID,
          version: 1,
        },
      ],
      financeApplicationId: FINANCE_ID,
      requestedAmountMinor: "3250000",
      status: "submitted",
    });
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({ functionName: "m3_get_finance_application" }),
    );
  });

  it("records exact lender-reported terms without a servicing model", async () => {
    const { application, gateway } = service(
      evidence({ finance_application_id: FINANCE_ID, status: "preparing" }),
    );

    await expect(
      application.createFinanceApplication(
        command({
          applicantPartyId: APPLICANT_ID,
          dealId: DEAL_ID,
          externalReference: "LENDER-SYNTHETIC-42",
          lenderPartyId: LENDER_ID,
          lenderReportedAnnualRate: "6.125",
          lenderReportedTermMonths: 60,
          notes: null,
          requestedAmount: {
            amountMinor: "3250000",
            currencyCode: "cad",
          },
        }),
      ),
    ).resolves.toMatchObject({
      financeApplicationId: FINANCE_ID,
      status: "preparing",
    });

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_create_finance_application",
        parameters: expect.objectContaining({
          p_lender_reported_annual_rate: "6.125",
          p_lender_reported_term_months: 60,
          p_requested_amount_minor: "3250000",
          p_requested_currency_code: "CAD",
        }),
      }),
    );
  });

  it("rejects recurring servicing material before invoking storage", async () => {
    const { application, gateway } = service([]);
    await expect(
      application.createFinanceApplication(
        command({
          applicantPartyId: APPLICANT_ID,
          dealId: DEAL_ID,
          externalReference: null,
          lenderPartyId: LENDER_ID,
          lenderReportedAnnualRate: null,
          lenderReportedTermMonths: null,
          notes: null,
          paymentSchedule: [{ dueAt: "2026-08-01" }],
          requestedAmount: {
            amountMinor: "1000000",
            currencyCode: "CAD",
          },
        }),
      ),
    ).rejects.toBeInstanceOf(M3ApplicationValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });

  it("requires a reason for adverse and cancellation transitions", async () => {
    const { application, gateway } = service([]);
    await expect(
      application.transitionFinanceApplication(
        entityCommand(
          { expectedVersion: 2, reason: null, targetStatus: "declined" },
          FINANCE_ID,
        ),
      ),
    ).rejects.toBeInstanceOf(M3ApplicationValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });

  it("adds a lender condition with application concurrency", async () => {
    const { application, gateway } = service(
      evidence({
        condition_id: CORRECTION_ID,
        finance_application_id: FINANCE_ID,
      }),
    );

    await application.addFinanceCondition(
      entityCommand(
        {
          conditionKey: "income_verification",
          description: "Lender requested synthetic income evidence",
          dueAt: "2026-07-30T12:00:00Z",
          expectedVersion: 3,
          required: true,
          satisfiedAt: null,
          supportingFileId: FILE_ID,
        },
        FINANCE_ID,
      ),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_add_finance_condition",
        parameters: expect.objectContaining({
          p_due_at: "2026-07-30T12:00:00Z",
          p_expected_version: 3,
          p_supporting_file_id: FILE_ID,
        }),
      }),
    );
  });

  it("replaces a lender condition using both application and condition versions", async () => {
    const { application, gateway } = service(
      evidence({
        condition_id: FILE_ID,
        finance_application_id: FINANCE_ID,
      }),
    );

    await expect(
      application.updateFinanceCondition({
        ...entityCommand(
          {
            description: "Updated synthetic income evidence",
            dueAt: "2026-08-01T12:00:00Z",
            expectedConditionVersion: 1,
            expectedVersion: 4,
            required: true,
            satisfiedAt: "2026-07-20T12:00:00Z",
            supportingFileId: FILE_ID,
          },
          FINANCE_ID,
        ),
        conditionId: CORRECTION_ID,
      }),
    ).resolves.toMatchObject({ conditionId: FILE_ID });

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_update_finance_condition",
        parameters: expect.objectContaining({
          p_condition_id: CORRECTION_ID,
          p_expected_condition_version: 1,
          p_expected_version: 4,
          p_finance_application_id: FINANCE_ID,
        }),
      }),
    );
  });
});

describe("T-PAY-001..003 / T-API-001 one-time money contracts", () => {
  it("records only a positive one-time transaction in canonical minor units", async () => {
    const { application, gateway } = service(
      evidence({ payment_transaction_id: PAYMENT_ID, status: "recorded" }),
    );

    await application.recordPaymentTransaction(
      entityCommand(
        {
          methodKey: "bank_transfer",
          money: { amountMinor: "150000", currencyCode: "cad" },
          notes: null,
          occurredAt: "2026-07-16T13:00:00-04:00",
          proofFileId: null,
          reference: "SYNTHETIC-RECEIPT",
          type: "deposit",
        },
        DEAL_ID,
      ),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_record_payment_transaction",
        parameters: expect.objectContaining({
          p_amount_minor: "150000",
          p_currency_code: "CAD",
          p_deal_id: DEAL_ID,
          p_occurred_at: "2026-07-16T17:00:00.000Z",
          p_transaction_type: "deposit",
        }),
      }),
    );
  });

  it("passes a neutral configured one-time event key to the pinned deal policy", async () => {
    const { application, gateway } = service(
      evidence({ payment_transaction_id: PAYMENT_ID, status: "recorded" }),
    );
    await application.recordPaymentTransaction(
      entityCommand(
        {
          methodKey: "internal_ledger",
          money: { amountMinor: "2500", currencyCode: "CAD" },
          notes: "Synthetic configured credit",
          occurredAt: "2026-07-16T17:00:00Z",
          proofFileId: null,
          reference: null,
          type: "configured.credit",
        },
        DEAL_ID,
      ),
    );
    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_record_payment_transaction",
        parameters: expect.objectContaining({
          p_transaction_type: "configured.credit",
        }),
      }),
    );
  });

  it("settles by expected version through a distinct command", async () => {
    const { application, gateway } = service(
      evidence({ payment_transaction_id: PAYMENT_ID, status: "settled" }),
    );

    await application.settlePaymentTransaction(
      entityCommand(
        { expectedVersion: 1, settledAt: "2026-07-16T18:00:00Z" },
        PAYMENT_ID,
      ),
    );

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_settle_payment_transaction",
        parameters: expect.objectContaining({
          p_expected_version: 1,
          p_payment_transaction_id: PAYMENT_ID,
          p_settled_at: "2026-07-16T18:00:00Z",
        }),
      }),
    );
  });

  it("creates a reasoned linked correction without mutating the original", async () => {
    const { application, gateway } = service(
      evidence({
        correction_transaction_id: CORRECTION_ID,
        original_transaction_id: PAYMENT_ID,
        remaining_minor: "100000",
        status: "settled",
      }),
    );

    await expect(
      application.correctPaymentTransaction(
        entityCommand(
          {
            correctionType: "refund",
            expectedVersion: 2,
            money: { amountMinor: "50000", currencyCode: "CAD" },
            reason: "Customer-requested partial refund",
          },
          PAYMENT_ID,
        ),
      ),
    ).resolves.toMatchObject({
      correctionTransactionId: CORRECTION_ID,
      originalTransactionId: PAYMENT_ID,
      remainingMinor: "100000",
    });

    expect(gateway.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "m3_correct_payment_transaction",
        parameters: expect.objectContaining({
          p_correction_type: "refund",
          p_expected_version: 2,
          p_original_transaction_id: PAYMENT_ID,
          p_reason: "Customer-requested partial refund",
        }),
      }),
    );
  });

  it("rejects a correction without an optimistic original version", async () => {
    const { application, gateway } = service([]);
    await expect(
      application.refundPaymentTransaction(
        entityCommand(
          {
            money: { amountMinor: "50000", currencyCode: "CAD" },
            reason: "Missing version must fail",
          },
          PAYMENT_ID,
        ),
      ),
    ).rejects.toBeInstanceOf(M3ApplicationValidationError);
    expect(gateway.invoke).not.toHaveBeenCalled();
  });

  it("rejects an over-broad ledger projection", async () => {
    const { application } = service([
      {
        amount_minor: "100",
        corrects_transaction_id: null,
        correction_reason: null,
        created_at: "2026-07-16T17:00:00Z",
        currency_code: "CAD",
        deal_id: DEAL_ID,
        last_updated_by_user_id: ACTOR_ID,
        method_key: "bank_transfer",
        notes: null,
        occurred_at: "2026-07-16T17:00:00Z",
        payment_transaction_id: PAYMENT_ID,
        proof_file_id: null,
        provider_secret: "must not cross the contract",
        recorded_by_user_id: ACTOR_ID,
        reference: null,
        settled_at: null,
        status: "recorded",
        transaction_type: "deposit",
        updated_at: "2026-07-16T17:00:00Z",
        version: 1,
      },
    ]);

    await expect(
      application.listPaymentTransactions({
        accessToken: "header.payload.signature",
        dealId: DEAL_ID,
        workspaceId: WORKSPACE_ID,
      }),
    ).rejects.toBeInstanceOf(M3RpcContractError);
  });

  it("returns the strict payment-ledger evidence required by the operator screen", async () => {
    const { application } = service([
      {
        amount_minor: "-2500",
        corrects_transaction_id: PAYMENT_ID,
        correction_reason: "Customer-requested correction",
        created_at: "2026-07-16T18:00:00Z",
        currency_code: "CAD",
        deal_id: DEAL_ID,
        last_updated_by_user_id: ACTOR_ID,
        method_key: null,
        notes: null,
        occurred_at: "2026-07-16T18:00:00Z",
        payment_transaction_id: "85000000-0000-4000-8000-000000000099",
        proof_file_id: null,
        recorded_by_user_id: ACTOR_ID,
        reference: null,
        settled_at: "2026-07-16T18:00:00Z",
        status: "settled",
        transaction_type: "refund",
        updated_at: "2026-07-16T18:00:00Z",
        version: 1,
      },
    ]);

    await expect(
      application.listPaymentTransactions({
        accessToken: "header.payload.signature",
        dealId: DEAL_ID,
        workspaceId: WORKSPACE_ID,
      }),
    ).resolves.toEqual([
      expect.objectContaining({
        correctsTransactionId: PAYMENT_ID,
        correctionReason: "Customer-requested correction",
        methodKey: null,
        recordedByUserId: ACTOR_ID,
        status: "settled",
      }),
    ]);
  });
});
