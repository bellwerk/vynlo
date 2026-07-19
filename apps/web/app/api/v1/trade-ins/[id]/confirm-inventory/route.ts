import { handleApplicationCommandRoute } from "../../../../../../lib/api/command-route";
import { createM3DealsApplicationService } from "../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM3DealsApplicationService,
    execute: (service, input) =>
      service.confirmTradeInInventory({ ...input, entityId: id }),
    successStatus: () => 200,
  });
}
