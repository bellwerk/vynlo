import { M3ApplicationValidationError } from "@vynlo/application";

import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../lib/api/command-route";
import {
  createM3DealsApplicationService,
  createVerticalSliceApplicationService,
} from "../../../../lib/api/postgrest";

const dealStatuses = [
  "draft",
  "active",
  "pending",
  "closed",
  "archived",
] as const;
type DealStatus = (typeof dealStatuses)[number];

function statusFrom(value: string | null): DealStatus | undefined {
  if (value === null) return undefined;
  if (!dealStatuses.includes(value as DealStatus)) {
    throw new M3ApplicationValidationError("invalid_request_body");
  }
  return value as DealStatus;
}

function isLegacyDealBody(body: unknown): boolean {
  return (
    typeof body === "object" &&
    body !== null &&
    !Array.isArray(body) &&
    "inventory" in body &&
    "participant" in body
  );
}

export async function GET(request: Request): Promise<Response> {
  return handleApplicationQueryRoute(request, {
    createService: createM3DealsApplicationService,
    execute: (service, metadata) => {
      const query = new URL(request.url).searchParams;
      const rawLimit = query.get("limit");
      return service.listDeals({
        accessToken: metadata.accessToken,
        ...(query.get("cursor_id") === null
          ? {}
          : { cursorId: query.get("cursor_id")! }),
        ...(query.get("cursor_updated_at") === null
          ? {}
          : { cursorUpdatedAt: query.get("cursor_updated_at")! }),
        ...(rawLimit === null ? {} : { limit: Number(rawLimit) }),
        ...(query.get("owner_membership_id") === null
          ? {}
          : { ownerMembershipId: query.get("owner_membership_id")! }),
        ...(statusFrom(query.get("status")) === undefined
          ? {}
          : { status: statusFrom(query.get("status"))! }),
        workspaceId: metadata.workspaceId,
      });
    },
  });
}

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: () => ({
      legacy: createVerticalSliceApplicationService(),
      m3: createM3DealsApplicationService(),
    }),
    execute: async (service, input) =>
      isLegacyDealBody(input.body)
        ? await service.legacy.createDealDraft(input)
        : await service.m3.createDeal(input),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
