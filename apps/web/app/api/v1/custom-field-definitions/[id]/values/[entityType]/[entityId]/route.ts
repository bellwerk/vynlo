import { handleApplicationCommandRoute } from "../../../../../../../../lib/api/command-route";
import { createM3ConfigurationApplicationService } from "../../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{
    readonly entityId: string;
    readonly entityType: string;
    readonly id: string;
  }>;
}

export async function PUT(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { entityId, entityType, id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM3ConfigurationApplicationService,
    execute: (service, input) =>
      service.setCustomFieldValue({
        ...input,
        customFieldDefinitionId: id,
        entityId,
        entityType,
      }),
    successStatus: () => 200,
  });
}
