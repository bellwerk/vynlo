import { z } from "zod";

import type {
  AuthenticatedRpcGateway,
  VerticalSliceCommandInput,
} from "./vertical-slice-api";

export const m3UuidSchema = z
  .string()
  .uuid()
  .transform((value) => value.toLowerCase());

export const m3KeySchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(1)
  .max(128)
  .regex(/^[a-z][a-z0-9_]*(?:[.-][a-z0-9_]+)*$/u);

export const m3ExpectedVersionSchema = z
  .number()
  .int()
  .min(1)
  .max(Number.MAX_SAFE_INTEGER);

export const m3TimestampSchema = z.iso.datetime({ offset: true });
export const m3NullableTimestampSchema = m3TimestampSchema.nullable();
export const m3DateSchema = z.iso.date();

export const m3CurrencyCodeSchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-Z]{3}$/u);

export const m3MinorUnitSchema = z
  .string()
  .trim()
  .regex(/^(?:0|-?[1-9][0-9]{0,18})$/u)
  .refine(
    (value) => {
      const amount = BigInt(value);
      return (
        amount >= -9_223_372_036_854_775_808n &&
        amount <= 9_223_372_036_854_775_807n
      );
    },
    { message: "Amount exceeds PostgreSQL bigint bounds." },
  );

export const m3PositiveMinorUnitSchema = m3MinorUnitSchema.refine(
  (value) => BigInt(value) > 0n,
  { message: "Amount must be positive." },
);

export const m3MoneySchema = z
  .object({
    amountMinor: m3MinorUnitSchema,
    currencyCode: m3CurrencyCodeSchema,
  })
  .strict();

export const m3PositiveMoneySchema = z
  .object({
    amountMinor: m3PositiveMinorUnitSchema,
    currencyCode: m3CurrencyCodeSchema,
  })
  .strict();

export const m3ReasonSchema = z.string().trim().min(1).max(2_000);

export const m3CommandEvidenceSchema = z
  .object({
    aggregate_version: m3ExpectedVersionSchema,
    audit_event_id: m3UuidSchema,
    outbox_event_id: m3UuidSchema,
    replayed: z.boolean(),
  })
  .strict();

export type M3ApplicationValidationErrorCode =
  | "invalid_request_body"
  | "invalid_entity_id"
  | "invalid_workflow_key"
  | "invalid_custom_field_definition_id";

export class M3ApplicationValidationError extends Error {
  readonly code: M3ApplicationValidationErrorCode;

  constructor(code: M3ApplicationValidationErrorCode) {
    super("The Milestone 3 request input is invalid.");
    this.name = "M3ApplicationValidationError";
    this.code = code;
  }
}

export class M3RpcContractError extends Error {
  constructor() {
    super("The Milestone 3 data store returned an invalid response.");
    this.name = "M3RpcContractError";
  }
}

export interface M3EntityCommandInput extends VerticalSliceCommandInput {
  readonly entityId: string;
}

export interface M3ApplicationServiceOptions {
  readonly gateway: AuthenticatedRpcGateway;
}

export function parseM3Body<T>(schema: z.ZodType<T>, body: unknown): T {
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    throw new M3ApplicationValidationError("invalid_request_body");
  }
  return parsed.data;
}

export function parseM3EntityId(entityId: unknown): string {
  const parsed = m3UuidSchema.safeParse(entityId);
  if (!parsed.success) {
    throw new M3ApplicationValidationError("invalid_entity_id");
  }
  return parsed.data;
}

export function parseM3RpcRow<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = z.array(schema).length(1).safeParse(value);
  if (!parsed.success) {
    throw new M3RpcContractError();
  }
  return parsed.data[0]!;
}

export function parseM3RpcRows<T>(
  schema: z.ZodType<T>,
  maximumRows: number,
  value: unknown,
): readonly T[] {
  const parsed = z.array(schema).max(maximumRows).safeParse(value);
  if (!parsed.success) {
    throw new M3RpcContractError();
  }
  return Object.freeze(parsed.data);
}
