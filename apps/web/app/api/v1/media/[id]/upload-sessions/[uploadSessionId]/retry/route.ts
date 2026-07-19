import { handleApplicationCommandRoute } from "../../../../../../../../lib/api/command-route";
import { createM2MediaApplicationService } from "../../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{
    readonly id: string;
    readonly uploadSessionId: string;
  }>;
}

export async function POST(request: Request, context: RouteContext) {
  const { id, uploadSessionId } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM2MediaApplicationService,
    execute: (service, input) =>
      service.retryUploadVerification({
        ...input,
        mediaId: id,
        uploadSessionId,
      }),
    successStatus: (result) => (result.replayed ? 200 : 202),
  });
}
