import { handleApplicationCommandRoute } from "../../../../../../../lib/api/command-route";
import { createVinDecodeApplicationService } from "../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly requestId: string }>;
}

export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { requestId } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createVinDecodeApplicationService,
    execute: (service, input) =>
      service.reviewDuplicate({ ...input, vinDecodeRequestId: requestId }),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
