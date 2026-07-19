import { handleApplicationQueryRoute } from "../../../../lib/api/command-route";
import { createM2InventoryApplicationService } from "../../../../lib/api/postgrest";

export async function GET(request: Request): Promise<Response> {
  return handleApplicationQueryRoute(request, {
    createService: createM2InventoryApplicationService,
    execute: (service, metadata) =>
      service.listActiveLocations({
        accessToken: metadata.accessToken,
        workspaceId: metadata.workspaceId,
      }),
  });
}
