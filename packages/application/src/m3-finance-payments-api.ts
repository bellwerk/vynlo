import {
  M3DealDomainError,
  normalizeFinanceApplicationCommand,
  normalizePaymentRecordCommand,
} from "@vynlo/deals";
import { z } from "zod";

import {
  M3ApplicationValidationError,
  m3CommandEvidenceSchema,
  m3CurrencyCodeSchema,
  m3ExpectedVersionSchema,
  m3KeySchema,
  m3NullableTimestampSchema,
  m3PositiveMoneySchema,
  m3ReasonSchema,
  m3TimestampSchema,
  m3UuidSchema,
  parseM3Body,
  parseM3EntityId,
  parseM3RpcRow,
  parseM3RpcRows,
  type M3EntityCommandInput,
} from "./m3-api-common";
import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

const nullableText = (maximum: number) =>
  z.string().trim().max(maximum).nullable();

const financeStatusSchema = z.enum([
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
]);

const lenderRateSchema = z
  .string()
  .regex(/^(?:0|[1-9][0-9]{0,2})(?:\.[0-9]{1,6})?$/u)
  .nullable();

const financeCreateBodySchema = z
  .object({
    applicantPartyId: m3UuidSchema,
    dealId: m3UuidSchema,
    externalReference: nullableText(500),
    lenderPartyId: m3UuidSchema,
    lenderReportedAnnualRate: lenderRateSchema,
    lenderReportedTermMonths: z.number().int().min(1).max(1_200).nullable(),
    notes: nullableText(4_000),
    requestedAmount: m3PositiveMoneySchema,
  })
  .strict();

const financeUpdateBodySchema = z
  .object({
    approvedAmount: m3PositiveMoneySchema.nullable().optional(),
    approvalExpiresAt: m3NullableTimestampSchema.optional(),
    customerAcceptedAt: m3NullableTimestampSchema.optional(),
    expectedVersion: m3ExpectedVersionSchema,
    externalReference: nullableText(500).optional(),
    fundedAt: m3NullableTimestampSchema.optional(),
    fundingReference: nullableText(500).optional(),
    lenderReportedAnnualRate: lenderRateSchema.optional(),
    lenderReportedTermMonths: z
      .number()
      .int()
      .min(1)
      .max(1_200)
      .nullable()
      .optional(),
    notes: nullableText(4_000).optional(),
    submittedAt: m3NullableTimestampSchema.optional(),
  })
  .strict()
  .refine(
    (body) => Object.keys(body).some((key) => key !== "expectedVersion"),
    { message: "At least one finance field must be updated." },
  );

const financeTransitionBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    reason: m3ReasonSchema.nullable(),
    targetStatus: financeStatusSchema,
  })
  .strict()
  .refine(
    (body) =>
      !["declined", "customer_declined", "cancelled"].includes(
        body.targetStatus,
      ) || body.reason !== null,
    { message: "A reason is required for this finance transition." },
  );

const financeConditionBodySchema = z
  .object({
    conditionKey: m3KeySchema,
    description: z.string().trim().min(1).max(2_000),
    dueAt: m3NullableTimestampSchema,
    expectedVersion: m3ExpectedVersionSchema,
    required: z.boolean(),
    satisfiedAt: m3NullableTimestampSchema,
    supportingFileId: m3UuidSchema.nullable(),
  })
  .strict();

const financeConditionUpdateBodySchema = z
  .object({
    description: z.string().trim().min(1).max(2_000),
    dueAt: m3NullableTimestampSchema,
    expectedConditionVersion: m3ExpectedVersionSchema,
    expectedVersion: m3ExpectedVersionSchema,
    required: z.boolean(),
    satisfiedAt: m3NullableTimestampSchema,
    supportingFileId: m3UuidSchema.nullable(),
  })
  .strict();

const paymentRecordBodySchema = z
  .object({
    methodKey: m3KeySchema,
    money: m3PositiveMoneySchema,
    notes: nullableText(4_000),
    occurredAt: m3TimestampSchema,
    proofFileId: m3UuidSchema.nullable(),
    reference: nullableText(500),
    type: m3KeySchema.refine(
      (value) => value !== "reversal" && value !== "refund",
    ),
  })
  .strict();

const paymentSettleBodySchema = z
  .object({
    expectedVersion: m3ExpectedVersionSchema,
    settledAt: m3TimestampSchema,
  })
  .strict();

const paymentCorrectionBodySchema = z
  .object({
    correctionType: z.enum(["reversal", "refund"]),
    expectedVersion: m3ExpectedVersionSchema,
    money: m3PositiveMoneySchema,
    reason: m3ReasonSchema,
  })
  .strict();

const paymentCorrectionDetailsBodySchema = paymentCorrectionBodySchema.omit({
  correctionType: true,
});

const financeResultSchema = m3CommandEvidenceSchema
  .extend({
    finance_application_id: m3UuidSchema,
    status: financeStatusSchema,
  })
  .strict();

const financeConditionResultSchema = m3CommandEvidenceSchema
  .extend({
    condition_id: m3UuidSchema,
    finance_application_id: m3UuidSchema,
  })
  .strict();

const paymentStatusSchema = z.enum(["recorded", "settled", "cancelled"]);
const paymentResultSchema = m3CommandEvidenceSchema
  .extend({
    payment_transaction_id: m3UuidSchema,
    status: paymentStatusSchema,
  })
  .strict();

const paymentCorrectionResultSchema = m3CommandEvidenceSchema
  .extend({
    correction_transaction_id: m3UuidSchema,
    original_transaction_id: m3UuidSchema,
    remaining_minor: z.string().regex(/^(?:0|[1-9][0-9]{0,18})$/u),
    status: z.literal("settled"),
  })
  .strict();

const financeListRowSchema = z
  .object({
    applicant_party_id: m3UuidSchema,
    approved_amount_minor: z
      .string()
      .regex(/^(?:0|[1-9][0-9]{0,18})$/u)
      .nullable(),
    currency_code: z.string().regex(/^[A-Z]{3}$/u),
    deal_id: m3UuidSchema,
    finance_application_id: m3UuidSchema,
    lender_party_id: m3UuidSchema,
    requested_amount_minor: z.string().regex(/^[1-9][0-9]{0,18}$/u),
    status: financeStatusSchema,
    updated_at: m3TimestampSchema,
    version: m3ExpectedVersionSchema,
  })
  .strict();

const financeConditionDetailSchema = z
  .object({
    condition_id: m3UuidSchema,
    condition_key: m3KeySchema,
    created_at: m3TimestampSchema,
    description: z.string().trim().min(1).max(2_000),
    due_at: m3NullableTimestampSchema,
    logical_condition_id: m3UuidSchema,
    replaces_condition_id: m3UuidSchema.nullable(),
    required: z.boolean(),
    satisfied_at: m3NullableTimestampSchema,
    status: z.literal("active"),
    supporting_file_id: m3UuidSchema.nullable(),
    version: m3ExpectedVersionSchema,
  })
  .strict();

const financeDetailRowSchema = z
  .object({
    applicant_party_id: m3UuidSchema,
    approval_expires_at: m3NullableTimestampSchema,
    approved_amount_minor: z
      .string()
      .regex(/^(?:0|[1-9][0-9]{0,18})$/u)
      .nullable(),
    conditions: z.array(financeConditionDetailSchema).max(100),
    created_at: m3TimestampSchema,
    currency_code: m3CurrencyCodeSchema,
    customer_accepted_at: m3NullableTimestampSchema,
    deal_id: m3UuidSchema,
    decision_at: m3NullableTimestampSchema,
    external_reference: nullableText(500),
    finance_application_id: m3UuidSchema,
    funded_at: m3NullableTimestampSchema,
    funding_reference: nullableText(500),
    lender_party_id: m3UuidSchema,
    lender_reported_annual_rate: lenderRateSchema,
    lender_reported_term_months: z.number().int().min(1).max(1_200).nullable(),
    notes: nullableText(4_000),
    requested_amount_minor: z.string().regex(/^[1-9][0-9]{0,18}$/u),
    status: financeStatusSchema,
    status_reason: nullableText(2_000),
    submitted_at: m3NullableTimestampSchema,
    updated_at: m3TimestampSchema,
    version: m3ExpectedVersionSchema,
  })
  .strict();

const paymentListRowSchema = z
  .object({
    amount_minor: z.string().regex(/^-?(?:0|[1-9][0-9]{0,18})$/u),
    corrects_transaction_id: m3UuidSchema.nullable(),
    correction_reason: nullableText(2_000),
    created_at: m3TimestampSchema,
    currency_code: z.string().regex(/^[A-Z]{3}$/u),
    deal_id: m3UuidSchema,
    last_updated_by_user_id: m3UuidSchema,
    method_key: m3KeySchema.nullable(),
    notes: nullableText(4_000),
    occurred_at: m3TimestampSchema,
    payment_transaction_id: m3UuidSchema,
    proof_file_id: m3UuidSchema.nullable(),
    recorded_by_user_id: m3UuidSchema,
    reference: nullableText(500),
    settled_at: m3NullableTimestampSchema,
    status: paymentStatusSchema,
    transaction_type: m3KeySchema,
    updated_at: m3TimestampSchema,
    version: m3ExpectedVersionSchema,
  })
  .strict();

export interface M3FinancePaymentQueryInput {
  readonly accessToken: string;
  readonly dealId?: string;
  readonly workspaceId: string;
}

export interface M3FinanceApplicationQueryInput {
  readonly accessToken: string;
  readonly financeApplicationId: string;
  readonly workspaceId: string;
}

export interface M3FinanceConditionCommandInput extends M3EntityCommandInput {
  readonly conditionId: string;
}

function normalizeDeal<T>(operation: () => T): T {
  try {
    return operation();
  } catch (error) {
    if (error instanceof M3DealDomainError) {
      throw new M3ApplicationValidationError("invalid_request_body");
    }
    throw error;
  }
}

function commandEvidence(row: z.infer<typeof m3CommandEvidenceSchema>) {
  return {
    aggregateVersion: row.aggregate_version,
    auditEventId: row.audit_event_id,
    outboxEventId: row.outbox_event_id,
    replayed: row.replayed,
  } as const;
}

export class M3FinancePaymentsApplicationService {
  readonly #gateway: AuthenticatedRpcGateway;

  constructor(gateway: AuthenticatedRpcGateway) {
    this.#gateway = gateway;
  }

  async listFinanceApplications(input: M3FinancePaymentQueryInput) {
    return parseM3RpcRows(
      financeListRowSchema,
      500,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_finance_applications",
        parameters: {
          p_deal_id:
            input.dealId === undefined ? null : parseM3EntityId(input.dealId),
          p_workspace_id: input.workspaceId,
        },
      }),
    ).map((row) => ({
      applicantPartyId: row.applicant_party_id,
      approvedAmountMinor: row.approved_amount_minor,
      currencyCode: row.currency_code,
      dealId: row.deal_id,
      financeApplicationId: row.finance_application_id,
      lenderPartyId: row.lender_party_id,
      requestedAmountMinor: row.requested_amount_minor,
      status: row.status,
      updatedAt: row.updated_at,
      version: row.version,
    }));
  }

  async getFinanceApplication(input: M3FinanceApplicationQueryInput) {
    const row = parseM3RpcRow(
      financeDetailRowSchema,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_get_finance_application",
        parameters: {
          p_finance_application_id: parseM3EntityId(input.financeApplicationId),
          p_workspace_id: input.workspaceId,
        },
      }),
    );
    return {
      applicantPartyId: row.applicant_party_id,
      approvalExpiresAt: row.approval_expires_at,
      approvedAmountMinor: row.approved_amount_minor,
      conditions: row.conditions.map((condition) => ({
        conditionId: condition.condition_id,
        conditionKey: condition.condition_key,
        createdAt: condition.created_at,
        description: condition.description,
        dueAt: condition.due_at,
        logicalConditionId: condition.logical_condition_id,
        replacesConditionId: condition.replaces_condition_id,
        required: condition.required,
        satisfiedAt: condition.satisfied_at,
        status: condition.status,
        supportingFileId: condition.supporting_file_id,
        version: condition.version,
      })),
      createdAt: row.created_at,
      currencyCode: row.currency_code,
      customerAcceptedAt: row.customer_accepted_at,
      dealId: row.deal_id,
      decisionAt: row.decision_at,
      externalReference: row.external_reference,
      financeApplicationId: row.finance_application_id,
      fundedAt: row.funded_at,
      fundingReference: row.funding_reference,
      lenderPartyId: row.lender_party_id,
      lenderReportedAnnualRate: row.lender_reported_annual_rate,
      lenderReportedTermMonths: row.lender_reported_term_months,
      notes: row.notes,
      requestedAmountMinor: row.requested_amount_minor,
      status: row.status,
      statusReason: row.status_reason,
      submittedAt: row.submitted_at,
      updatedAt: row.updated_at,
      version: row.version,
    } as const;
  }

  async createFinanceApplication(input: VerticalSliceCommandInput) {
    const body = parseM3Body(financeCreateBodySchema, input.body);
    const command = normalizeDeal(() =>
      normalizeFinanceApplicationCommand({
        ...body,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseM3RpcRow(
      financeResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_create_finance_application",
        parameters: {
          p_applicant_party_id: command.applicantPartyId,
          p_correlation_id: input.metadata.correlationId,
          p_deal_id: command.dealId,
          p_external_reference: command.externalReference,
          p_idempotency_key: command.idempotencyKey,
          p_lender_party_id: command.lenderPartyId,
          p_lender_reported_annual_rate: command.lenderReportedAnnualRate,
          p_lender_reported_term_months: command.lenderReportedTermMonths,
          p_notes: command.notes,
          p_request_id: input.metadata.requestId,
          p_requested_amount_minor: command.requestedAmount.amountMinor,
          p_requested_currency_code: command.requestedAmount.currencyCode,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      financeApplicationId: row.finance_application_id,
      status: row.status,
    };
  }

  async updateFinanceApplication(input: M3EntityCommandInput) {
    const applicationId = parseM3EntityId(input.entityId);
    const body = parseM3Body(financeUpdateBodySchema, input.body);
    const row = parseM3RpcRow(
      financeResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_update_finance_application",
        parameters: {
          p_approval_expires_at: body.approvalExpiresAt ?? null,
          p_approved_amount_minor: body.approvedAmount?.amountMinor ?? null,
          p_approved_currency_code: body.approvedAmount?.currencyCode ?? null,
          p_correlation_id: input.metadata.correlationId,
          p_customer_accepted_at: body.customerAcceptedAt ?? null,
          p_expected_version: body.expectedVersion,
          p_external_reference: body.externalReference ?? null,
          p_finance_application_id: applicationId,
          p_funded_at: body.fundedAt ?? null,
          p_funding_reference: body.fundingReference ?? null,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_lender_reported_annual_rate: body.lenderReportedAnnualRate ?? null,
          p_lender_reported_term_months: body.lenderReportedTermMonths ?? null,
          p_notes: body.notes ?? null,
          p_request_id: input.metadata.requestId,
          p_submitted_at: body.submittedAt ?? null,
          p_update_approval_amount: body.approvedAmount !== undefined,
          p_update_approval_expiry: body.approvalExpiresAt !== undefined,
          p_update_customer_acceptance: body.customerAcceptedAt !== undefined,
          p_update_external_reference: body.externalReference !== undefined,
          p_update_funded_at: body.fundedAt !== undefined,
          p_update_funding_reference: body.fundingReference !== undefined,
          p_update_lender_rate: body.lenderReportedAnnualRate !== undefined,
          p_update_lender_term: body.lenderReportedTermMonths !== undefined,
          p_update_notes: body.notes !== undefined,
          p_update_submitted_at: body.submittedAt !== undefined,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      financeApplicationId: row.finance_application_id,
      status: row.status,
    };
  }

  async transitionFinanceApplication(input: M3EntityCommandInput) {
    const applicationId = parseM3EntityId(input.entityId);
    const body = parseM3Body(financeTransitionBodySchema, input.body);
    const row = parseM3RpcRow(
      financeResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_transition_finance_application",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: body.expectedVersion,
          p_finance_application_id: applicationId,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_target_status: body.targetStatus,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      financeApplicationId: row.finance_application_id,
      status: row.status,
    };
  }

  async addFinanceCondition(input: M3EntityCommandInput) {
    const applicationId = parseM3EntityId(input.entityId);
    const body = parseM3Body(financeConditionBodySchema, input.body);
    const row = parseM3RpcRow(
      financeConditionResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_add_finance_condition",
        parameters: {
          p_condition_key: body.conditionKey,
          p_correlation_id: input.metadata.correlationId,
          p_description: body.description,
          p_due_at: body.dueAt,
          p_expected_version: body.expectedVersion,
          p_finance_application_id: applicationId,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_request_id: input.metadata.requestId,
          p_required: body.required,
          p_satisfied_at: body.satisfiedAt,
          p_supporting_file_id: body.supportingFileId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      conditionId: row.condition_id,
      financeApplicationId: row.finance_application_id,
    };
  }

  async updateFinanceCondition(input: M3FinanceConditionCommandInput) {
    const applicationId = parseM3EntityId(input.entityId);
    const conditionId = parseM3EntityId(input.conditionId);
    const body = parseM3Body(financeConditionUpdateBodySchema, input.body);
    const row = parseM3RpcRow(
      financeConditionResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_update_finance_condition",
        parameters: {
          p_condition_id: conditionId,
          p_correlation_id: input.metadata.correlationId,
          p_description: body.description,
          p_due_at: body.dueAt,
          p_expected_condition_version: body.expectedConditionVersion,
          p_expected_version: body.expectedVersion,
          p_finance_application_id: applicationId,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_request_id: input.metadata.requestId,
          p_required: body.required,
          p_satisfied_at: body.satisfiedAt,
          p_supporting_file_id: body.supportingFileId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      conditionId: row.condition_id,
      financeApplicationId: row.finance_application_id,
    } as const;
  }

  async listPaymentTransactions(input: M3FinancePaymentQueryInput) {
    if (input.dealId === undefined) {
      throw new M3ApplicationValidationError("invalid_entity_id");
    }
    return parseM3RpcRows(
      paymentListRowSchema,
      500,
      await this.#gateway.invoke({
        accessToken: input.accessToken,
        functionName: "m3_list_payment_transactions",
        parameters: {
          p_deal_id: parseM3EntityId(input.dealId),
          p_workspace_id: input.workspaceId,
        },
      }),
    ).map((row) => ({
      amountMinor: row.amount_minor,
      correctsTransactionId: row.corrects_transaction_id,
      correctionReason: row.correction_reason,
      createdAt: row.created_at,
      currencyCode: row.currency_code,
      dealId: row.deal_id,
      lastUpdatedByUserId: row.last_updated_by_user_id,
      methodKey: row.method_key,
      notes: row.notes,
      occurredAt: row.occurred_at,
      paymentTransactionId: row.payment_transaction_id,
      proofFileId: row.proof_file_id,
      recordedByUserId: row.recorded_by_user_id,
      reference: row.reference,
      settledAt: row.settled_at,
      status: row.status,
      transactionType: row.transaction_type,
      updatedAt: row.updated_at,
      version: row.version,
    }));
  }

  async recordPaymentTransaction(input: M3EntityCommandInput) {
    const dealId = parseM3EntityId(input.entityId);
    const body = parseM3Body(paymentRecordBodySchema, input.body);
    const command = normalizeDeal(() =>
      normalizePaymentRecordCommand({
        ...body,
        dealCurrencyCode: body.money.currencyCode,
        dealId,
        idempotencyKey: input.metadata.idempotencyKey,
      }),
    );
    const row = parseM3RpcRow(
      paymentResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_record_payment_transaction",
        parameters: {
          p_amount_minor: command.money.amountMinor,
          p_correlation_id: input.metadata.correlationId,
          p_currency_code: command.money.currencyCode,
          p_deal_id: command.dealId,
          p_idempotency_key: command.idempotencyKey,
          p_method_key: command.methodKey,
          p_notes: command.notes,
          p_occurred_at: command.occurredAt,
          p_proof_file_id: command.proofFileId,
          p_reference: command.reference,
          p_request_id: input.metadata.requestId,
          p_transaction_type: command.type,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      paymentTransactionId: row.payment_transaction_id,
      status: row.status,
    };
  }

  async settlePaymentTransaction(input: M3EntityCommandInput) {
    const transactionId = parseM3EntityId(input.entityId);
    const body = parseM3Body(paymentSettleBodySchema, input.body);
    const row = parseM3RpcRow(
      paymentResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_settle_payment_transaction",
        parameters: {
          p_correlation_id: input.metadata.correlationId,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_payment_transaction_id: transactionId,
          p_request_id: input.metadata.requestId,
          p_settled_at: body.settledAt,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      paymentTransactionId: row.payment_transaction_id,
      status: row.status,
    };
  }

  async correctPaymentTransaction(input: M3EntityCommandInput) {
    return this.#correctPaymentTransaction(input, null);
  }

  async refundPaymentTransaction(input: M3EntityCommandInput) {
    return this.#correctPaymentTransaction(input, "refund");
  }

  async reversePaymentTransaction(input: M3EntityCommandInput) {
    return this.#correctPaymentTransaction(input, "reversal");
  }

  async #correctPaymentTransaction(
    input: M3EntityCommandInput,
    forcedType: "refund" | "reversal" | null,
  ) {
    const transactionId = parseM3EntityId(input.entityId);
    const body =
      forcedType === null
        ? parseM3Body(paymentCorrectionBodySchema, input.body)
        : {
            ...parseM3Body(paymentCorrectionDetailsBodySchema, input.body),
            correctionType: forcedType,
          };
    const row = parseM3RpcRow(
      paymentCorrectionResultSchema,
      await this.#gateway.invoke({
        accessToken: input.metadata.accessToken,
        functionName: "m3_correct_payment_transaction",
        parameters: {
          p_amount_minor: body.money.amountMinor,
          p_correlation_id: input.metadata.correlationId,
          p_correction_type: body.correctionType,
          p_currency_code: body.money.currencyCode,
          p_expected_version: body.expectedVersion,
          p_idempotency_key: input.metadata.idempotencyKey,
          p_original_transaction_id: transactionId,
          p_reason: body.reason,
          p_request_id: input.metadata.requestId,
          p_workspace_id: input.metadata.workspaceId,
        },
      }),
    );
    return {
      ...commandEvidence(row),
      correctionTransactionId: row.correction_transaction_id,
      originalTransactionId: row.original_transaction_id,
      remainingMinor: row.remaining_minor,
      status: row.status,
    };
  }
}
