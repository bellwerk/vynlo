const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VIN_PATTERN = /^[A-HJ-NPR-Z0-9]{17}$/;
const CURRENCY_PATTERN = /^[A-Z]{3}$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export type InventoryCommandErrorCode =
  | "invalid_idempotency_key"
  | "invalid_stock_definition_id"
  | "invalid_vin"
  | "invalid_model_year"
  | "invalid_vehicle_text"
  | "invalid_acquisition_date"
  | "invalid_odometer"
  | "invalid_currency"
  | "invalid_money_minor"
  | "invalid_public_notes"
  | "invalid_stock_format";

export class InventoryCommandError extends Error {
  readonly code: InventoryCommandErrorCode;

  constructor(code: InventoryCommandErrorCode) {
    super(code);
    this.name = "InventoryCommandError";
    this.code = code;
  }
}

export interface CreateInventoryUnitCommand {
  readonly idempotencyKey: string;
  readonly stockNumberDefinitionId: string;
  readonly vin: string;
  readonly modelYear: number | null;
  readonly make: string | null;
  readonly model: string | null;
  readonly acquisitionDate: string | null;
  readonly odometer: Readonly<{
    value: number;
    unit: "km" | "mi";
  }> | null;
  readonly currencyCode: string;
  readonly advertisedPriceMinor: number | null;
  readonly publicNotes: string | null;
}

export interface NormalizedCreateInventoryUnitCommand extends CreateInventoryUnitCommand {
  readonly vin: string;
  readonly make: string | null;
  readonly model: string | null;
  readonly currencyCode: string;
  readonly publicNotes: string | null;
}

function normalizeOptionalText(
  value: string | null,
  maximumLength: number,
  code: InventoryCommandErrorCode,
): string | null {
  if (value === null) {
    return null;
  }

  const normalized = value.trim();
  if (!normalized || normalized.length > maximumLength) {
    throw new InventoryCommandError(code);
  }

  return normalized;
}

function isValidDateOnly(value: string): boolean {
  if (!DATE_PATTERN.test(value)) {
    return false;
  }

  const [year, month, day] = value.split("-").map(Number);
  const instant = new Date(Date.UTC(year ?? 0, (month ?? 0) - 1, day ?? 0));
  return (
    instant.getUTCFullYear() === year &&
    instant.getUTCMonth() === (month ?? 0) - 1 &&
    instant.getUTCDate() === day
  );
}

export function normalizeVinInput(value: string): string {
  const normalized = value.trim().toUpperCase();
  if (!VIN_PATTERN.test(normalized)) {
    throw new InventoryCommandError("invalid_vin");
  }
  return normalized;
}

export function normalizeCreateInventoryUnitCommand(
  command: CreateInventoryUnitCommand,
): NormalizedCreateInventoryUnitCommand {
  const idempotencyKey = command.idempotencyKey.trim();
  if (idempotencyKey.length < 8 || idempotencyKey.length > 200) {
    throw new InventoryCommandError("invalid_idempotency_key");
  }

  if (!UUID_PATTERN.test(command.stockNumberDefinitionId)) {
    throw new InventoryCommandError("invalid_stock_definition_id");
  }

  if (
    command.modelYear !== null &&
    (!Number.isInteger(command.modelYear) ||
      command.modelYear < 1886 ||
      command.modelYear > 2200)
  ) {
    throw new InventoryCommandError("invalid_model_year");
  }

  if (
    command.acquisitionDate !== null &&
    !isValidDateOnly(command.acquisitionDate)
  ) {
    throw new InventoryCommandError("invalid_acquisition_date");
  }

  if (
    command.odometer !== null &&
    (!Number.isSafeInteger(command.odometer.value) ||
      command.odometer.value < 0)
  ) {
    throw new InventoryCommandError("invalid_odometer");
  }

  const currencyCode = command.currencyCode.trim().toUpperCase();
  if (!CURRENCY_PATTERN.test(currencyCode)) {
    throw new InventoryCommandError("invalid_currency");
  }

  if (
    command.advertisedPriceMinor !== null &&
    (!Number.isSafeInteger(command.advertisedPriceMinor) ||
      command.advertisedPriceMinor < 0)
  ) {
    throw new InventoryCommandError("invalid_money_minor");
  }

  const publicNotes =
    command.publicNotes === null || command.publicNotes.trim() === ""
      ? null
      : normalizeOptionalText(
          command.publicNotes,
          4_000,
          "invalid_public_notes",
        );

  return Object.freeze({
    ...command,
    idempotencyKey,
    vin: normalizeVinInput(command.vin),
    make: normalizeOptionalText(command.make, 100, "invalid_vehicle_text"),
    model: normalizeOptionalText(command.model, 100, "invalid_vehicle_text"),
    currencyCode,
    publicNotes,
  });
}

export function formatStockNumber(
  prefix: string,
  numericWidth: number,
  sequenceValue: number,
): string {
  if (
    prefix.length > 32 ||
    !Number.isInteger(numericWidth) ||
    numericWidth < 1 ||
    numericWidth > 18 ||
    !Number.isSafeInteger(sequenceValue) ||
    sequenceValue < 1
  ) {
    throw new InventoryCommandError("invalid_stock_format");
  }

  return `${prefix}${String(sequenceValue).padStart(numericWidth, "0")}`;
}
