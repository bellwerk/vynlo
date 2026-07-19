import { handleApplicationCommandRoute } from "../../../../../lib/api/command-route";
import { createVinDecodeApplicationService } from "../../../../../lib/api/postgrest";

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createVinDecodeApplicationService,
    execute: (service, input) => service.requestDecode(input),
    successStatus: (result) => (result.replayed ? 200 : 202),
  });
}
