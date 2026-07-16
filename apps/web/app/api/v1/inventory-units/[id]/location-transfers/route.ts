import { handleApplicationCommandRoute } from "../../../../../../lib/api/command-route";
import { createM2InventoryApplicationService } from "../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM2InventoryApplicationService,
    execute: (service, input) =>
      service.transferLocation({ ...input, inventoryUnitId: id }),
    successStatus: () => 200,
  });
}
