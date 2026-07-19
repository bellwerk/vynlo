import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../lib/api/command-route";
import { createM3CrmApplicationService } from "../../../../lib/api/postgrest";

export async function GET(request: Request): Promise<Response> {
  return handleApplicationQueryRoute(request, {
    createService: createM3CrmApplicationService,
    execute: (service, metadata) =>
      service.listLeads({
        accessToken: metadata.accessToken,
        workspaceId: metadata.workspaceId,
      }),
  });
}

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM3CrmApplicationService,
    execute: (service, input) => service.createLead(input),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
