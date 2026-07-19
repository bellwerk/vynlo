import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../../lib/api/command-route";
import { createM3CrmApplicationService } from "../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM3CrmApplicationService,
    execute: (service, metadata) =>
      service.getLead({
        accessToken: metadata.accessToken,
        leadId: id,
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
    createService: createM3CrmApplicationService,
    execute: (service, input) => service.updateLead({ ...input, entityId: id }),
    successStatus: () => 200,
  });
}
