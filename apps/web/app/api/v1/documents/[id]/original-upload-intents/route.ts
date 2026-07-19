import { handleApplicationCommandRoute } from "../../../../../../lib/api/command-route";
import { createLegalOriginalApplicationService } from "../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function POST(request: Request, context: RouteContext) {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createLegalOriginalApplicationService,
    execute: (service, input) =>
      service.createUploadIntent({ ...input, documentId: id }),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
