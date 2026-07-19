import { handleApplicationQueryRoute } from "../../../../../../../lib/api/command-route";
import { createLegalOriginalApplicationService } from "../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{
    readonly id: string;
    readonly uploadSessionId: string;
  }>;
}

export async function GET(request: Request, context: RouteContext) {
  const { id, uploadSessionId } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createLegalOriginalApplicationService,
    execute: (service, metadata) =>
      service.getUploadStatus({
        documentId: id,
        metadata: {
          accessToken: metadata.accessToken,
          workspaceId: metadata.workspaceId,
        },
        uploadSessionId,
      }),
  });
}
