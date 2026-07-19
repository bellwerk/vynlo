import { handleApplicationQueryRoute } from "../../../../../../lib/api/command-route";
import { createM2MediaApplicationService } from "../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM2MediaApplicationService,
    execute: (service, metadata) =>
      service.listInventoryMedia({
        accessToken: metadata.accessToken,
        inventoryUnitId: id,
        workspaceId: metadata.workspaceId,
      }),
  });
}
