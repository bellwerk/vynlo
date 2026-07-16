import { handleApplicationCommandRoute } from "../../../../../lib/api/command-route";
import { createWorkspaceInvitationApplicationService } from "../../../../../lib/api/postgrest";

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createWorkspaceInvitationApplicationService,
    execute: (service, input) => service.acceptWorkspaceInvitation(input),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
