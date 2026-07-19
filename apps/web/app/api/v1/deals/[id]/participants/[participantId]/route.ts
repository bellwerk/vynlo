import { handleApplicationCommandRoute } from "../../../../../../../lib/api/command-route";
import { createM3DealsApplicationService } from "../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{
    readonly id: string;
    readonly participantId: string;
  }>;
}

export async function DELETE(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id, participantId } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM3DealsApplicationService,
    execute: (service, input) =>
      service.releaseParticipant({
        ...input,
        childId: participantId,
        entityId: id,
      }),
    successStatus: () => 204,
  });
}
