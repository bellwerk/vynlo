import { handleApplicationQueryRoute } from "../../../../../../../lib/api/command-route";
import { createM2MediaApplicationService } from "../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{
    readonly id: string;
    readonly uploadSessionId: string;
  }>;
}

export async function GET(request: Request, context: RouteContext) {
  const { id, uploadSessionId } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM2MediaApplicationService,
    execute: (service, metadata) =>
      service.getUploadVerificationStatus({
        accessToken: metadata.accessToken,
        mediaId: id,
        uploadSessionId,
        workspaceId: metadata.workspaceId,
      }),
  });
}
