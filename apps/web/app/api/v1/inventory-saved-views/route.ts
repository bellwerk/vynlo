import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../lib/api/command-route";
import { createM2CostSearchApplicationService } from "../../../../lib/api/postgrest";

export async function GET(request: Request): Promise<Response> {
  const includeArchived = new URL(request.url).searchParams.get(
    "includeArchived",
  );
  return handleApplicationQueryRoute(request, {
    createService: createM2CostSearchApplicationService,
    execute: (service, metadata) =>
      service.listSavedViews({
        accessToken: metadata.accessToken,
        includeArchived: includeArchived === "true",
        workspaceId: metadata.workspaceId,
      }),
  });
}

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM2CostSearchApplicationService,
    execute: (service, input) => service.saveView(input),
    successStatus: (result) => (result.created ? 201 : 200),
  });
}
