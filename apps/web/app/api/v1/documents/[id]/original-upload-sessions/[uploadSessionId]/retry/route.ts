import { handleApplicationCommandRoute } from "../../../../../../../../lib/api/command-route";
import { createLegalOriginalApplicationService } from "../../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{
    readonly id: string;
    readonly uploadSessionId: string;
  }>;
}

export async function POST(request: Request, context: RouteContext) {
  const { id, uploadSessionId } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createLegalOriginalApplicationService,
    execute: (service, input) =>
      service.retryVerification({
        ...input,
        documentId: id,
        uploadSessionId,
      }),
    successStatus: (result) => (result.replayed ? 200 : 202),
  });
}
