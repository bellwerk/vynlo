import { handleApplicationCommandRoute } from "../../../../../../../../lib/api/command-route";
import { createM3CrmApplicationService } from "../../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{
    readonly id: string;
    readonly identifierId: string;
  }>;
}

export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id, identifierId } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM3CrmApplicationService,
    execute: (service, input) =>
      service.revealPartyIdentifier({
        ...input,
        childId: identifierId,
        entityId: id,
      }),
    successStatus: () => 200,
  });
}
