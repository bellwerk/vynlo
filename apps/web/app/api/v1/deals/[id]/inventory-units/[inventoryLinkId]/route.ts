import { handleApplicationCommandRoute } from "../../../../../../../lib/api/command-route";
import { createM3DealsApplicationService } from "../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{
    readonly id: string;
    readonly inventoryLinkId: string;
  }>;
}

export async function DELETE(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id, inventoryLinkId } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM3DealsApplicationService,
    execute: (service, input) =>
      service.releaseInventory({
        ...input,
        childId: inventoryLinkId,
        entityId: id,
      }),
    successStatus: () => 204,
  });
}
