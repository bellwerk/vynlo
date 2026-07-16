import { handleApplicationCommandRoute } from "../../../../../../lib/api/command-route";
import { createM2CostSearchApplicationService } from "../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM2CostSearchApplicationService,
    execute: (service, input) =>
      service.archiveView({ ...input, entityId: id }),
    successStatus: () => 200,
  });
}
