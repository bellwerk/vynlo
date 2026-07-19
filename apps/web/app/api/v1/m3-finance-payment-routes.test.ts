import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  GET as listPayments,
  POST as recordPayment,
} from "./deals/[id]/payment-transactions/route";
import { POST as transitionFinance } from "./finance-applications/[id]/transition/route";
import { PATCH as updateFinanceCondition } from "./finance-applications/[id]/conditions/[conditionId]/route";
import { POST as createFinance } from "./finance-applications/route";
import { POST as refundPayment } from "./payment-transactions/[id]/refund/route";
import { POST as reversePayment } from "./payment-transactions/[id]/reverse/route";
import { POST as settlePayment } from "./payment-transactions/[id]/settle/route";

const WORKSPACE_ID = "10000000-0000-4000-8000-000000000001";
const DEAL_ID = "20000000-0000-4000-8000-000000000001";
const APPLICANT_ID = "30000000-0000-4000-8000-000000000001";
const LENDER_ID = "40000000-0000-4000-8000-000000000001";
const FINANCE_ID = "50000000-0000-4000-8000-000000000001";
const PAYMENT_ID = "60000000-0000-4000-8000-000000000001";
const CORRECTION_ID = "70000000-0000-4000-8000-000000000001";
const USER_ID = "71000000-0000-4000-8000-000000000001";
const AUDIT_ID = "80000000-0000-4000-8000-000000000001";
const OUTBOX_ID = "90000000-0000-4000-8000-000000000001";
const CORRELATION_ID = "a0000000-0000-4000-8000-000000000001";

function request(path: string, body?: unknown, method = "POST"): Request {
  return new Request(`http://localhost${path}`, {
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    headers: {
      Authorization: "Bearer header.payload.signature",
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      ...(method === "GET" ? {} : { "Idempotency-Key": "m3-money-route-0001" }),
      "X-Correlation-Id": CORRELATION_ID,
      "X-Request-Id": "m3-money-request-0001",
      "X-Workspace-Id": WORKSPACE_ID,
    },
    method,
  });
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

describe("T-FIN-001 / T-PAY-001..003 / T-API-001 M3 money routes", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv(
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
      "sb_publishable_public_project_key_material",
    );
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("records exact lender-reported terms without servicing input", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(
        evidence({ finance_application_id: FINANCE_ID, status: "preparing" }),
      ),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await createFinance(
      request("/api/v1/finance-applications", {
        applicantPartyId: APPLICANT_ID,
        dealId: DEAL_ID,
        externalReference: "SYNTHETIC-LENDER-1",
        lenderPartyId: LENDER_ID,
        lenderReportedAnnualRate: "5.875",
        lenderReportedTermMonths: 48,
        notes: null,
        requestedAmount: { amountMinor: "3000000", currencyCode: "CAD" },
      }),
    );

    expect(response.status).toBe(201);
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_lender_reported_annual_rate: "5.875",
      p_requested_amount_minor: "3000000",
      p_workspace_id: WORKSPACE_ID,
    });
  });

  it("rejects recurring schedule fields and adverse transitions without a reason", async () => {
    const fetchImplementation = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchImplementation);

    const financeResponse = await createFinance(
      request("/api/v1/finance-applications", {
        applicantPartyId: APPLICANT_ID,
        dealId: DEAL_ID,
        externalReference: null,
        lenderPartyId: LENDER_ID,
        lenderReportedAnnualRate: null,
        lenderReportedTermMonths: null,
        notes: null,
        repaymentSchedule: [],
        requestedAmount: { amountMinor: "3000000", currencyCode: "CAD" },
      }),
    );
    const transitionResponse = await transitionFinance(
      request(`/api/v1/finance-applications/${FINANCE_ID}/transition`, {
        expectedVersion: 1,
        reason: null,
        targetStatus: "declined",
      }),
      { params: Promise.resolve({ id: FINANCE_ID }) },
    );

    expect(financeResponse.status).toBe(422);
    expect(transitionResponse.status).toBe(422);
    expect(fetchImplementation).not.toHaveBeenCalled();
  });

  it("replaces a finance condition with both concurrency versions", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(
        evidence({
          condition_id: CORRECTION_ID,
          finance_application_id: FINANCE_ID,
        }),
      ),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await updateFinanceCondition(
      request(
        `/api/v1/finance-applications/${FINANCE_ID}/conditions/${CORRECTION_ID}`,
        {
          description: "Updated synthetic lender condition",
          dueAt: null,
          expectedConditionVersion: 2,
          expectedVersion: 4,
          required: true,
          satisfiedAt: "2026-07-20T12:00:00Z",
          supportingFileId: null,
        },
        "PATCH",
      ),
      {
        params: Promise.resolve({ conditionId: CORRECTION_ID, id: FINANCE_ID }),
      },
    );

    expect(response.status).toBe(200);
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_condition_id: CORRECTION_ID,
      p_expected_condition_version: 2,
      p_expected_version: 4,
      p_finance_application_id: FINANCE_ID,
    });
  });

  it("records and lists one-time payments as canonical strings", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (input) =>
      String(input).endsWith("m3_list_payment_transactions")
        ? Response.json([
            {
              amount_minor: "250000",
              corrects_transaction_id: null,
              correction_reason: null,
              created_at: "2026-07-16T17:00:00Z",
              currency_code: "CAD",
              deal_id: DEAL_ID,
              last_updated_by_user_id: USER_ID,
              method_key: "bank_transfer",
              notes: "Synthetic payment",
              occurred_at: "2026-07-16T17:00:00Z",
              payment_transaction_id: PAYMENT_ID,
              proof_file_id: null,
              recorded_by_user_id: USER_ID,
              reference: "SYNTHETIC-REF",
              settled_at: null,
              status: "recorded",
              transaction_type: "deposit",
              updated_at: "2026-07-16T17:00:00Z",
              version: 1,
            },
          ])
        : Response.json(
            evidence({
              payment_transaction_id: PAYMENT_ID,
              status: "recorded",
            }),
          ),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const recordResponse = await recordPayment(
      request(`/api/v1/deals/${DEAL_ID}/payment-transactions`, {
        methodKey: "bank_transfer",
        money: { amountMinor: "250000", currencyCode: "CAD" },
        notes: null,
        occurredAt: "2026-07-16T17:00:00Z",
        proofFileId: null,
        reference: "SYNTHETIC-DEP",
        type: "deposit",
      }),
      { params: Promise.resolve({ id: DEAL_ID }) },
    );
    const listResponse = await listPayments(
      request(
        `/api/v1/deals/${DEAL_ID}/payment-transactions`,
        undefined,
        "GET",
      ),
      { params: Promise.resolve({ id: DEAL_ID }) },
    );

    expect(recordResponse.status).toBe(201);
    expect(listResponse.status).toBe(200);
    await expect(listResponse.json()).resolves.toMatchObject({
      data: [{ amountMinor: "250000", paymentTransactionId: PAYMENT_ID }],
    });
  });

  it("settles a recorded transaction using expected-version concurrency", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      Response.json(
        evidence({ payment_transaction_id: PAYMENT_ID, status: "settled" }),
      ),
    );
    vi.stubGlobal("fetch", fetchImplementation);

    const response = await settlePayment(
      request(`/api/v1/payment-transactions/${PAYMENT_ID}/settle`, {
        expectedVersion: 1,
        settledAt: "2026-07-16T18:00:00Z",
      }),
      { params: Promise.resolve({ id: PAYMENT_ID }) },
    );

    expect(response.status).toBe(200);
    expect(
      JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
    ).toMatchObject({
      p_expected_version: 1,
      p_payment_transaction_id: PAYMENT_ID,
    });
  });

  it.each([
    ["refund", refundPayment],
    ["reversal", reversePayment],
  ] as const)(
    "forces the route-specific %s correction type",
    async (correctionType, handler) => {
      const fetchImplementation = vi.fn<typeof fetch>(async () =>
        Response.json(
          evidence({
            correction_transaction_id: CORRECTION_ID,
            original_transaction_id: PAYMENT_ID,
            remaining_minor: "200000",
            status: "settled",
          }),
        ),
      );
      vi.stubGlobal("fetch", fetchImplementation);

      const response = await handler(
        request(
          `/api/v1/payment-transactions/${PAYMENT_ID}/${correctionType}`,
          {
            expectedVersion: 2,
            money: { amountMinor: "50000", currencyCode: "CAD" },
            reason: "Synthetic correction",
          },
        ),
        { params: Promise.resolve({ id: PAYMENT_ID }) },
      );

      expect(response.status).toBe(201);
      expect(
        JSON.parse(String(fetchImplementation.mock.calls[0]?.[1]?.body)),
      ).toMatchObject({
        p_correction_type: correctionType,
        p_expected_version: 2,
        p_original_transaction_id: PAYMENT_ID,
      });
    },
  );
});
