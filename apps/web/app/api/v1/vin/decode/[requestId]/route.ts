import { handleApplicationQueryRoute } from "../../../../../../lib/api/command-route";
import { createVinDecodeApplicationService } from "../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly requestId: string }>;
}

export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { requestId } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createVinDecodeApplicationService,
    execute: (service, metadata) =>
      service.getStatus({
        metadata: {
          accessToken: metadata.accessToken,
          workspaceId: metadata.workspaceId,
        },
        vinDecodeRequestId: requestId,
      }),
  });
}
