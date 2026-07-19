import { handleApplicationQueryRoute } from "../../../../../../../lib/api/command-route";
import { createM3ConfigurationApplicationService } from "../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{
    readonly entityId: string;
    readonly entityType: string;
  }>;
}

export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { entityId, entityType } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM3ConfigurationApplicationService,
    execute: (service, metadata) =>
      service.getCustomFieldValues({
        accessToken: metadata.accessToken,
        entityId,
        entityType,
        workspaceId: metadata.workspaceId,
      }),
  });
}
