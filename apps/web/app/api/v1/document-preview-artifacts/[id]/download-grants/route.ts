import { handleApplicationCommandRoute } from "../../../../../../lib/api/command-route";
import { createDocumentPreviewDownloadApplicationService } from "../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createDocumentPreviewDownloadApplicationService,
    execute: (service, input) =>
      service.authorize({ ...input, artifactId: id }),
    successStatus: () => 200,
  });
}
