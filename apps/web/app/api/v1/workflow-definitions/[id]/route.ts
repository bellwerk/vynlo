import { handleApplicationQueryRoute } from "../../../../../lib/api/command-route";
import { createM3ConfigurationApplicationService } from "../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM3ConfigurationApplicationService,
    execute: (service, metadata) =>
      service.readWorkflowDefinition({
        accessToken: metadata.accessToken,
        workflowDefinitionId: id,
        workspaceId: metadata.workspaceId,
      }),
  });
}
