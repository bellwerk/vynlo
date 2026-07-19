import { handleApplicationCommandRoute } from "../../../../lib/api/command-route";
import { createM3ConfigurationApplicationService } from "../../../../lib/api/postgrest";

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM3ConfigurationApplicationService,
    execute: (service, input) => service.createWorkflowVersion(input),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
