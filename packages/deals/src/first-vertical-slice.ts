const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KEY_PATTERN = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/;
const CURRENCY_PATTERN = /^[A-Z]{3}$/;

export type DealDraftCommandErrorCode =
  | "invalid_idempotency_key"
  | "invalid_deal_type_key"
  | "invalid_currency"
  | "invalid_party_id"
  | "invalid_participant_role_key"
  | "invalid_inventory_unit_id"
  | "invalid_inventory_role_key"
  | "invalid_notes";

export class DealDraftCommandError extends Error {
  readonly code: DealDraftCommandErrorCode;

  constructor(code: DealDraftCommandErrorCode) {
    super(code);
    this.name = "DealDraftCommandError";
    this.code = code;
  }
}

export interface CreateDealDraftCommand {
  readonly idempotencyKey: string;
  readonly dealTypeKey: string;
  readonly currencyCode: string;
  readonly participant: Readonly<{
    partyId: string;
    roleKey: string;
  }>;
  readonly inventory: Readonly<{
    inventoryUnitId: string;
    roleKey: string;
  }>;
  readonly notes: string | null;
}

export function normalizeCreateDealDraftCommand(
  command: CreateDealDraftCommand,
): Readonly<CreateDealDraftCommand> {
  const idempotencyKey = command.idempotencyKey.trim();
  if (idempotencyKey.length < 8 || idempotencyKey.length > 200) {
    throw new DealDraftCommandError("invalid_idempotency_key");
  }

  const dealTypeKey = command.dealTypeKey.trim().toLowerCase();
  if (!KEY_PATTERN.test(dealTypeKey)) {
    throw new DealDraftCommandError("invalid_deal_type_key");
  }

  const currencyCode = command.currencyCode.trim().toUpperCase();
  if (!CURRENCY_PATTERN.test(currencyCode)) {
    throw new DealDraftCommandError("invalid_currency");
  }

  if (!UUID_PATTERN.test(command.participant.partyId)) {
    throw new DealDraftCommandError("invalid_party_id");
  }

  const participantRoleKey = command.participant.roleKey.trim().toLowerCase();
  if (!KEY_PATTERN.test(participantRoleKey)) {
    throw new DealDraftCommandError("invalid_participant_role_key");
  }

  if (!UUID_PATTERN.test(command.inventory.inventoryUnitId)) {
    throw new DealDraftCommandError("invalid_inventory_unit_id");
  }

  const inventoryRoleKey = command.inventory.roleKey.trim().toLowerCase();
  if (!KEY_PATTERN.test(inventoryRoleKey)) {
    throw new DealDraftCommandError("invalid_inventory_role_key");
  }

  const notes = command.notes?.trim() || null;
  if (notes !== null && notes.length > 4_000) {
    throw new DealDraftCommandError("invalid_notes");
  }

  return Object.freeze({
    idempotencyKey,
    dealTypeKey,
    currencyCode,
    participant: Object.freeze({
      partyId: command.participant.partyId.toLowerCase(),
      roleKey: participantRoleKey,
    }),
    inventory: Object.freeze({
      inventoryUnitId: command.inventory.inventoryUnitId.toLowerCase(),
      roleKey: inventoryRoleKey,
    }),
    notes,
  });
}
