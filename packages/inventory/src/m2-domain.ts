import { normalizeVinInput } from "./first-vertical-slice";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const CURRENCY_PATTERN = /^[A-Z]{3}$/u;
const CONDITION_KEY_PATTERN = /^[a-z][a-z0-9_.-]{0,63}$/u;
const DATE_ONLY_PATTERN = /^\d{4}-\d{2}-\d{2}$/u;
const NON_NEGATIVE_INTEGER_PATTERN = /^(?:0|[1-9]\d*)$/u;
const POSTGRES_BIGINT_MAX = 9_223_372_036_854_775_807n;
const MILLISECONDS_PER_DAY = 86_400_000;

export const INVENTORY_UPDATE_PERMISSION = "inventory.update" as const;
export const INVENTORY_READ_INTERNAL_PERMISSION =
  "inventory.read_internal" as const;
export const INVENTORY_UPDATE_INTERNAL_PERMISSION =
  "inventory.update_internal" as const;

export type InventoryDomainErrorCode =
  | "invalid_vin"
  | "invalid_identifier"
  | "workspace_context_mismatch"
  | "vehicle_holding_identity_conflict"
  | "invalid_holding_episode"
  | "open_holding_episode_exists"
  | "invalid_currency"
  | "invalid_money_minor"
  | "money_currency_mismatch"
  | "permission_required"
  | "invalid_expected_version"
  | "inventory_version_conflict"
  | "invalid_inventory_update"
  | "empty_inventory_update"
  | "invalid_condition_key"
  | "invalid_location_id"
  | "location_unchanged"
  | "location_reason_required"
  | "invalid_notes"
  | "internal_notes_boundary"
  | "invalid_date"
  | "invalid_days_in_stock_range"
  | "invalid_cost_entry";

export class InventoryDomainError extends Error {
  readonly code: InventoryDomainErrorCode;

  constructor(code: InventoryDomainErrorCode) {
    super(code);
    this.name = "InventoryDomainError";
    this.code = code;
  }
}

function hasOwn(value: object, key: PropertyKey): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function requireUuid(value: unknown, code: InventoryDomainErrorCode): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new InventoryDomainError(code);
  }
  return value.toLowerCase();
}

function requireVersion(value: unknown): number {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < 1 ||
    (value as number) >= Number.MAX_SAFE_INTEGER
  ) {
    throw new InventoryDomainError("invalid_expected_version");
  }
  return value as number;
}

function requirePermission(
  effectivePermissionKeys: readonly string[],
  permissionKey: string,
): void {
  if (!effectivePermissionKeys.includes(permissionKey)) {
    throw new InventoryDomainError("permission_required");
  }
}

function parseDateOnly(value: unknown): number {
  if (typeof value !== "string" || !DATE_ONLY_PATTERN.test(value)) {
    throw new InventoryDomainError("invalid_date");
  }

  const [year, month, day] = value.split("-").map(Number);
  const instant = Date.UTC(year ?? 0, (month ?? 0) - 1, day ?? 0);
  const parsed = new Date(instant);
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== (month ?? 0) - 1 ||
    parsed.getUTCDate() !== day
  ) {
    throw new InventoryDomainError("invalid_date");
  }
  return instant;
}

function normalizeNotes(value: unknown, maximumLength: number): string | null {
  if (value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw new InventoryDomainError("invalid_notes");
  }
  const normalized = value.trim();
  if (normalized.length > maximumLength) {
    throw new InventoryDomainError("invalid_notes");
  }
  return normalized || null;
}

/** Manual keyboard and paste are the only VIN input modes in Release 1. */
export function normalizeTypedOrPastedVin(value: unknown): string {
  if (typeof value !== "string") {
    throw new InventoryDomainError("invalid_vin");
  }
  try {
    return normalizeVinInput(value);
  } catch {
    throw new InventoryDomainError("invalid_vin");
  }
}

export interface PhysicalVehicleSnapshot {
  readonly id: string;
  readonly workspaceId: string;
  readonly vin: string;
  readonly factsVersion: number;
}

export interface InventoryHoldingEpisodeSnapshot {
  readonly id: string;
  readonly workspaceId: string;
  readonly vehicleId: string;
  readonly canonicalStatus:
    "draft" | "active" | "pending" | "closed" | "archived";
  readonly acquiredOn: string;
  readonly closedOn: string | null;
}

export interface OpenInventoryHoldingPlan {
  readonly inventoryUnitId: string;
  readonly vehicleId: string;
  readonly acquiredOn: string;
  readonly initialCanonicalStatus: "draft";
  readonly reacquisition: boolean;
  readonly previousHoldingEpisodeIds: readonly string[];
}

/**
 * Plans a new holding episode without ever treating the physical vehicle as the
 * inventory aggregate. Persistence must repeat this check while locking the
 * workspace/vehicle rows.
 */
export function planOpenInventoryHolding(input: {
  readonly authoritativeWorkspaceId: string;
  readonly inventoryUnitId: string;
  readonly acquiredOn: string;
  readonly vehicle: PhysicalVehicleSnapshot;
  readonly existingEpisodes: readonly InventoryHoldingEpisodeSnapshot[];
}): Readonly<OpenInventoryHoldingPlan> {
  const authoritativeWorkspaceId = requireUuid(
    input.authoritativeWorkspaceId,
    "invalid_identifier",
  );
  const vehicleId = requireUuid(input.vehicle.id, "invalid_identifier");
  const inventoryUnitId = requireUuid(
    input.inventoryUnitId,
    "invalid_identifier",
  );
  const vehicleWorkspaceId = requireUuid(
    input.vehicle.workspaceId,
    "invalid_identifier",
  );
  const acquiredAt = parseDateOnly(input.acquiredOn);

  if (vehicleWorkspaceId !== authoritativeWorkspaceId) {
    throw new InventoryDomainError("workspace_context_mismatch");
  }
  if (vehicleId === inventoryUnitId) {
    throw new InventoryDomainError("vehicle_holding_identity_conflict");
  }
  normalizeTypedOrPastedVin(input.vehicle.vin);
  requireVersion(input.vehicle.factsVersion);

  const episodeIds = new Set<string>();
  const previousHoldingEpisodeIds: string[] = [];
  for (const episode of input.existingEpisodes) {
    const episodeId = requireUuid(episode.id, "invalid_holding_episode");
    const episodeWorkspaceId = requireUuid(
      episode.workspaceId,
      "invalid_holding_episode",
    );
    const episodeVehicleId = requireUuid(
      episode.vehicleId,
      "invalid_holding_episode",
    );
    if (
      episodeIds.has(episodeId) ||
      episodeId === inventoryUnitId ||
      episodeWorkspaceId !== authoritativeWorkspaceId ||
      episodeVehicleId !== vehicleId
    ) {
      throw new InventoryDomainError("invalid_holding_episode");
    }
    episodeIds.add(episodeId);

    const episodeAcquiredAt = parseDateOnly(episode.acquiredOn);
    const openEpisode = ["draft", "active", "pending"].includes(
      episode.canonicalStatus,
    );
    if (openEpisode) {
      if (episode.closedOn !== null) {
        throw new InventoryDomainError("invalid_holding_episode");
      }
      throw new InventoryDomainError("open_holding_episode_exists");
    }
    if (
      !["closed", "archived"].includes(episode.canonicalStatus) ||
      episode.closedOn === null
    ) {
      throw new InventoryDomainError("invalid_holding_episode");
    }
    const episodeClosedAt = parseDateOnly(episode.closedOn);
    if (episodeClosedAt < episodeAcquiredAt || acquiredAt < episodeClosedAt) {
      throw new InventoryDomainError("invalid_holding_episode");
    }
    previousHoldingEpisodeIds.push(episodeId);
  }

  return Object.freeze({
    inventoryUnitId,
    vehicleId,
    acquiredOn: input.acquiredOn,
    initialCanonicalStatus: "draft",
    reacquisition: previousHoldingEpisodeIds.length > 0,
    previousHoldingEpisodeIds: Object.freeze(previousHoldingEpisodeIds),
  });
}

export interface InventoryMoney {
  readonly minorUnits: bigint;
  readonly currencyCode: string;
}

function parseMinorUnits(value: unknown): bigint {
  let minorUnits: bigint;
  if (typeof value === "bigint") {
    minorUnits = value;
  } else if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) {
      throw new InventoryDomainError("invalid_money_minor");
    }
    minorUnits = BigInt(value);
  } else if (
    typeof value === "string" &&
    value.trim().length <= 19 &&
    NON_NEGATIVE_INTEGER_PATTERN.test(value.trim())
  ) {
    minorUnits = BigInt(value.trim());
  } else {
    throw new InventoryDomainError("invalid_money_minor");
  }

  if (minorUnits < 0n || minorUnits > POSTGRES_BIGINT_MAX) {
    throw new InventoryDomainError("invalid_money_minor");
  }
  return minorUnits;
}

export function normalizeCurrencyCode(value: unknown): string {
  if (typeof value !== "string") {
    throw new InventoryDomainError("invalid_currency");
  }
  const normalized = value.trim().toUpperCase();
  if (!CURRENCY_PATTERN.test(normalized)) {
    throw new InventoryDomainError("invalid_currency");
  }
  return normalized;
}

/** Parses a non-negative Postgres bigint price without binary floating point. */
export function parseInventoryPrice(input: {
  readonly minorUnits: unknown;
  readonly currencyCode: unknown;
}): Readonly<InventoryMoney> {
  return Object.freeze({
    minorUnits: parseMinorUnits(input.minorUnits),
    currencyCode: normalizeCurrencyCode(input.currencyCode),
  });
}

export interface InventoryUnitMutableSnapshot {
  readonly id: string;
  readonly vehicleId: string;
  readonly version: number;
  readonly currencyCode: string;
  readonly conditionKey: string | null;
  readonly locationId: string | null;
  readonly advertisedPrice: InventoryMoney | null;
  readonly expectedSalePrice: InventoryMoney | null;
  readonly publicNotes: string | null;
  readonly internalNotes: string | null;
}

export interface InventoryUnitUpdateCommand {
  readonly expectedVersion: number;
  readonly conditionKey?: string | null;
  readonly locationId?: string;
  readonly locationChangeReason?: string;
  readonly advertisedPrice?: Readonly<{
    readonly minorUnits: unknown;
    readonly currencyCode: unknown;
  }> | null;
  readonly expectedSalePrice?: Readonly<{
    readonly minorUnits: unknown;
    readonly currencyCode: unknown;
  }> | null;
  readonly publicNotes?: string | null;
}

export interface InventoryLocationTransfer {
  readonly fromLocationId: string | null;
  readonly toLocationId: string;
  readonly reason: string;
}

export interface InventoryUpdatePlan {
  readonly previousVersion: number;
  readonly nextVersion: number;
  readonly changedFields: readonly (
    | "advertised_price"
    | "condition"
    | "expected_sale_price"
    | "location"
    | "public_notes"
  )[];
  readonly locationTransfer: InventoryLocationTransfer | null;
  readonly next: Readonly<InventoryUnitMutableSnapshot>;
}

type MutableInventorySnapshotChanges = {
  -readonly [
    Key in keyof InventoryUnitMutableSnapshot
  ]?: InventoryUnitMutableSnapshot[Key];
};

const UPDATE_COMMAND_KEYS = new Set([
  "expectedVersion",
  "conditionKey",
  "locationId",
  "locationChangeReason",
  "advertisedPrice",
  "expectedSalePrice",
  "publicNotes",
]);

function assertAllowedKeys(
  value: object,
  allowedKeys: ReadonlySet<string>,
  internalBoundary: boolean,
): void {
  for (const key of Object.keys(value)) {
    if (!allowedKeys.has(key)) {
      throw new InventoryDomainError(
        internalBoundary && key === "internalNotes"
          ? "internal_notes_boundary"
          : "invalid_inventory_update",
      );
    }
  }
}

function normalizePriceForUnit(
  value: Readonly<{
    readonly minorUnits: unknown;
    readonly currencyCode: unknown;
  }> | null,
  unitCurrencyCode: string,
): Readonly<InventoryMoney> | null {
  if (value === null) {
    return null;
  }
  const price = parseInventoryPrice(value);
  if (price.currencyCode !== unitCurrencyCode) {
    throw new InventoryDomainError("money_currency_mismatch");
  }
  return price;
}

function moneyEquals(
  left: InventoryMoney | null,
  right: InventoryMoney | null,
): boolean {
  return (
    left === right ||
    (left !== null &&
      right !== null &&
      left.minorUnits === right.minorUnits &&
      left.currencyCode === right.currencyCode)
  );
}

function cloneSnapshot(
  snapshot: InventoryUnitMutableSnapshot,
  changes: MutableInventorySnapshotChanges,
): Readonly<InventoryUnitMutableSnapshot> {
  const next = { ...snapshot, ...changes };
  return Object.freeze({
    ...next,
    advertisedPrice:
      next.advertisedPrice === null
        ? null
        : parseInventoryPrice(next.advertisedPrice),
    expectedSalePrice:
      next.expectedSalePrice === null
        ? null
        : parseInventoryPrice(next.expectedSalePrice),
  });
}

/**
 * Validates a public inventory update. Internal notes are deliberately absent
 * from this command and rejected at runtime if an untyped caller injects them.
 */
export function planInventoryUnitUpdate(input: {
  readonly current: InventoryUnitMutableSnapshot;
  readonly command: InventoryUnitUpdateCommand;
  readonly effectivePermissionKeys: readonly string[];
}): Readonly<InventoryUpdatePlan> {
  assertAllowedKeys(input.command, UPDATE_COMMAND_KEYS, true);
  requirePermission(input.effectivePermissionKeys, INVENTORY_UPDATE_PERMISSION);

  const expectedVersion = requireVersion(input.command.expectedVersion);
  if (input.current.version !== expectedVersion) {
    throw new InventoryDomainError("inventory_version_conflict");
  }
  const currencyCode = normalizeCurrencyCode(input.current.currencyCode);
  const changes: MutableInventorySnapshotChanges = {};
  const changedFields: InventoryUpdatePlan["changedFields"][number][] = [];
  let locationTransfer: InventoryLocationTransfer | null = null;

  if (hasOwn(input.command, "conditionKey")) {
    const value = input.command.conditionKey;
    let conditionKey: string | null;
    if (value === null) {
      conditionKey = null;
    } else if (
      typeof value === "string" &&
      CONDITION_KEY_PATTERN.test(value.trim())
    ) {
      conditionKey = value.trim();
    } else {
      throw new InventoryDomainError("invalid_condition_key");
    }
    if (conditionKey !== input.current.conditionKey) {
      changes.conditionKey = conditionKey;
      changedFields.push("condition");
    }
  }

  if (hasOwn(input.command, "locationId")) {
    const locationId = requireUuid(
      input.command.locationId,
      "invalid_location_id",
    );
    if (locationId === input.current.locationId) {
      throw new InventoryDomainError("location_unchanged");
    }
    const reason =
      typeof input.command.locationChangeReason === "string"
        ? input.command.locationChangeReason.trim()
        : "";
    if (!reason || reason.length > 1_000) {
      throw new InventoryDomainError("location_reason_required");
    }
    changes.locationId = locationId;
    changedFields.push("location");
    locationTransfer = Object.freeze({
      fromLocationId: input.current.locationId,
      toLocationId: locationId,
      reason,
    });
  } else if (hasOwn(input.command, "locationChangeReason")) {
    throw new InventoryDomainError("invalid_inventory_update");
  }

  if (hasOwn(input.command, "advertisedPrice")) {
    const price = normalizePriceForUnit(
      input.command.advertisedPrice ?? null,
      currencyCode,
    );
    if (!moneyEquals(price, input.current.advertisedPrice)) {
      changes.advertisedPrice = price;
      changedFields.push("advertised_price");
    }
  }

  if (hasOwn(input.command, "expectedSalePrice")) {
    const price = normalizePriceForUnit(
      input.command.expectedSalePrice ?? null,
      currencyCode,
    );
    if (!moneyEquals(price, input.current.expectedSalePrice)) {
      changes.expectedSalePrice = price;
      changedFields.push("expected_sale_price");
    }
  }

  if (hasOwn(input.command, "publicNotes")) {
    const publicNotes = normalizeNotes(
      input.command.publicNotes ?? null,
      4_000,
    );
    if (publicNotes !== input.current.publicNotes) {
      changes.publicNotes = publicNotes;
      changedFields.push("public_notes");
    }
  }

  if (changedFields.length === 0) {
    throw new InventoryDomainError("empty_inventory_update");
  }

  const nextVersion = expectedVersion + 1;
  const next = cloneSnapshot(input.current, {
    ...changes,
    version: nextVersion,
  });

  return Object.freeze({
    previousVersion: expectedVersion,
    nextVersion,
    changedFields: Object.freeze(changedFields),
    locationTransfer,
    next,
  });
}

export interface InventoryInternalNotesUpdateCommand {
  readonly expectedVersion: number;
  readonly internalNotes: string | null;
}

const INTERNAL_NOTES_COMMAND_KEYS = new Set([
  "expectedVersion",
  "internalNotes",
]);

/** Internal notes require their own permission and command boundary. */
export function planInventoryInternalNotesUpdate(input: {
  readonly current: InventoryUnitMutableSnapshot;
  readonly command: InventoryInternalNotesUpdateCommand;
  readonly effectivePermissionKeys: readonly string[];
}): Readonly<InventoryUnitMutableSnapshot> {
  assertAllowedKeys(input.command, INTERNAL_NOTES_COMMAND_KEYS, false);
  requirePermission(
    input.effectivePermissionKeys,
    INVENTORY_UPDATE_INTERNAL_PERMISSION,
  );
  const expectedVersion = requireVersion(input.command.expectedVersion);
  if (input.current.version !== expectedVersion) {
    throw new InventoryDomainError("inventory_version_conflict");
  }
  const internalNotes = normalizeNotes(input.command.internalNotes, 8_000);
  if (internalNotes === input.current.internalNotes) {
    throw new InventoryDomainError("empty_inventory_update");
  }
  return cloneSnapshot(input.current, {
    internalNotes,
    version: expectedVersion + 1,
  });
}

export function readInventoryInternalNotes(
  snapshot: Pick<InventoryUnitMutableSnapshot, "internalNotes">,
  effectivePermissionKeys: readonly string[],
): string | null {
  requirePermission(
    effectivePermissionKeys,
    INVENTORY_READ_INTERNAL_PERMISSION,
  );
  return snapshot.internalNotes;
}

/** Creates the ordinary resource projection without copying internal notes. */
export function withoutInventoryInternalNotes<
  T extends Readonly<{ internalNotes: string | null }>,
>(snapshot: T): Readonly<Omit<T, "internalNotes">> {
  const { internalNotes: _internalNotes, ...external } = snapshot;
  void _internalNotes;
  return Object.freeze(external);
}

/**
 * Calendar-day aging. Callers provide workspace-local date-only values; a
 * closed holding stops aging on its closure date.
 */
export function calculateDaysInStock(input: {
  readonly acquiredOn: string;
  readonly asOf: string;
  readonly closedOn?: string | null;
}): number {
  const acquiredAt = parseDateOnly(input.acquiredOn);
  const asOf = parseDateOnly(input.asOf);
  const closedAt = input.closedOn ? parseDateOnly(input.closedOn) : undefined;
  if (asOf < acquiredAt || (closedAt !== undefined && closedAt < acquiredAt)) {
    throw new InventoryDomainError("invalid_days_in_stock_range");
  }
  const effectiveEnd = closedAt === undefined ? asOf : Math.min(asOf, closedAt);
  return Math.floor((effectiveEnd - acquiredAt) / MILLISECONDS_PER_DAY);
}

export interface InventoryCostContribution {
  readonly entryId: string;
  readonly status: "draft" | "posted" | "voided";
  readonly kind: "cost" | "reversal";
  readonly amount: InventoryMoney;
}

export interface EstimatedInventoryGross {
  readonly basis: "expected_sale_price" | "advertised_price";
  readonly currencyCode: string;
  readonly basisPriceMinor: bigint;
  readonly postedCostMinor: bigint;
  readonly postedReversalMinor: bigint;
  readonly netCostMinor: bigint;
  readonly estimatedGrossMinor: bigint;
}

/**
 * Estimated gross is the preferred expected sale price (falling back to the
 * advertised price) minus the effective posted cost ledger. It does not imply
 * realized gross, tax, financing, or tenant-contract allocation.
 */
export function calculateEstimatedInventoryGross(input: {
  readonly expectedSalePrice: InventoryMoney | null;
  readonly advertisedPrice: InventoryMoney | null;
  readonly costEntries: readonly InventoryCostContribution[];
}): Readonly<EstimatedInventoryGross> | null {
  const expectedSalePrice =
    input.expectedSalePrice === null
      ? null
      : parseInventoryPrice(input.expectedSalePrice);
  const advertisedPrice =
    input.advertisedPrice === null
      ? null
      : parseInventoryPrice(input.advertisedPrice);
  if (
    expectedSalePrice !== null &&
    advertisedPrice !== null &&
    expectedSalePrice.currencyCode !== advertisedPrice.currencyCode
  ) {
    throw new InventoryDomainError("money_currency_mismatch");
  }
  const basis =
    expectedSalePrice !== null
      ? "expected_sale_price"
      : advertisedPrice !== null
        ? "advertised_price"
        : null;
  const basisPrice = expectedSalePrice ?? advertisedPrice;
  if (basis === null || basisPrice === null) {
    return null;
  }
  const entryIds = new Set<string>();
  let postedCostMinor = 0n;
  let postedReversalMinor = 0n;

  for (const entry of input.costEntries) {
    const entryId =
      typeof entry.entryId === "string" ? entry.entryId.trim() : "";
    if (!entryId || entryIds.has(entryId)) {
      throw new InventoryDomainError("invalid_cost_entry");
    }
    entryIds.add(entryId);
    if (
      !["draft", "posted", "voided"].includes(entry.status) ||
      !["cost", "reversal"].includes(entry.kind)
    ) {
      throw new InventoryDomainError("invalid_cost_entry");
    }
    const amount = parseInventoryPrice(entry.amount);
    if (amount.currencyCode !== basisPrice.currencyCode) {
      throw new InventoryDomainError("money_currency_mismatch");
    }
    if (entry.status !== "posted") {
      continue;
    }
    if (entry.kind === "cost") {
      postedCostMinor += amount.minorUnits;
    } else {
      postedReversalMinor += amount.minorUnits;
    }
  }

  const netCostMinor = postedCostMinor - postedReversalMinor;
  if (netCostMinor < 0n) {
    throw new InventoryDomainError("invalid_cost_entry");
  }
  return Object.freeze({
    basis,
    currencyCode: basisPrice.currencyCode,
    basisPriceMinor: basisPrice.minorUnits,
    postedCostMinor,
    postedReversalMinor,
    netCostMinor,
    estimatedGrossMinor: basisPrice.minorUnits - netCostMinor,
  });
}
