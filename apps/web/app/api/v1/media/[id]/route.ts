import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../../lib/api/command-route";
import { createM2MediaApplicationService } from "../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM2MediaApplicationService,
    execute: (service, metadata) =>
      service.getAsset({
        accessToken: metadata.accessToken,
        mediaId: id,
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
    createService: createM2MediaApplicationService,
    execute: (service, input) =>
      service.updateCaption({ ...input, mediaId: id }),
    successStatus: () => 200,
  });
}
