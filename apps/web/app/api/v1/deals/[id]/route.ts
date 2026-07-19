import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../../lib/api/command-route";
import { createM3DealsApplicationService } from "../../../../../lib/api/postgrest";

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
    execute: (service, metadata) =>
      service.getDeal({
        accessToken: metadata.accessToken,
        dealId: id,
        workspaceId: metadata.workspaceId,
      }),
  });
}

export async function PATCH(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM3DealsApplicationService,
    execute: (service, input) => service.updateDeal({ ...input, entityId: id }),
    successStatus: () => 200,
  });
}
