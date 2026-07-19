import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../lib/api/command-route";
import { createM3CrmApplicationService } from "../../../../lib/api/postgrest";

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  return handleApplicationQueryRoute(request, {
    createService: createM3CrmApplicationService,
    execute: (service, metadata) =>
      service.listTimeline({
        accessToken: metadata.accessToken,
        dealId: url.searchParams.get("deal_id"),
        leadId: url.searchParams.get("lead_id"),
        partyId: url.searchParams.get("party_id"),
        workspaceId: metadata.workspaceId,
      }),
  });
}

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM3CrmApplicationService,
    execute: (service, input) => service.createActivity(input),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
