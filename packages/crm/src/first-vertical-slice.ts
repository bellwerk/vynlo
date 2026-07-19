export const PARTY_TYPES = ["person", "organization"] as const;

export type PartyType = (typeof PARTY_TYPES)[number];

export type PartyCommandErrorCode =
  "invalid_idempotency_key" | "invalid_party_type" | "invalid_display_name";

export class PartyCommandError extends Error {
  readonly code: PartyCommandErrorCode;

  constructor(code: PartyCommandErrorCode) {
    super(code);
    this.name = "PartyCommandError";
    this.code = code;
  }
}

export interface CreatePartyCommand {
  readonly idempotencyKey: string;
  readonly partyType: PartyType;
  readonly displayName: string;
}

export function normalizeCreatePartyCommand(
  command: CreatePartyCommand,
): Readonly<CreatePartyCommand> {
  const idempotencyKey = command.idempotencyKey.trim();
  if (idempotencyKey.length < 8 || idempotencyKey.length > 200) {
    throw new PartyCommandError("invalid_idempotency_key");
  }

  if (!PARTY_TYPES.includes(command.partyType)) {
    throw new PartyCommandError("invalid_party_type");
  }

  const displayName = command.displayName.trim().replace(/\s+/g, " ");
  if (!displayName || displayName.length > 200) {
    throw new PartyCommandError("invalid_display_name");
  }

  return Object.freeze({
    idempotencyKey,
    partyType: command.partyType,
    displayName,
  });
}
