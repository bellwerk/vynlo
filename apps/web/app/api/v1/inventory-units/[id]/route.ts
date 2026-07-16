import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../../lib/api/command-route";
import { createM2InventoryApplicationService } from "../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM2InventoryApplicationService,
    execute: (service, metadata) =>
      service.getOperations({
        accessToken: metadata.accessToken,
        inventoryUnitId: id,
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
    createService: createM2InventoryApplicationService,
    execute: (service, input) =>
      service.updateDetails({ ...input, inventoryUnitId: id }),
    successStatus: () => 200,
  });
}
