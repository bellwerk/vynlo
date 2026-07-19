import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../../../lib/api/command-route";
import { createM3DealsApplicationService } from "../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM3DealsApplicationService,
    execute: (service, metadata) => {
      const query = new URL(request.url).searchParams;
      const rawLimit = query.get("limit");
      const rawSortOrder = query.get("cursor_sort_order");
      return service.listDealLineItems({
        accessToken: metadata.accessToken,
        ...(query.get("cursor_id") === null
          ? {}
          : { cursorId: query.get("cursor_id")! }),
        ...(rawSortOrder === null
          ? {}
          : { cursorSortOrder: Number(rawSortOrder) }),
        dealId: id,
        ...(rawLimit === null ? {} : { limit: Number(rawLimit) }),
        workspaceId: metadata.workspaceId,
      });
    },
  });
}

export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM3DealsApplicationService,
    execute: (service, input) =>
      service.addLineItem({ ...input, entityId: id }),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
