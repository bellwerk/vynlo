import { handleCommandRoute } from "../../../../lib/api/command-route";

export async function POST(request: Request): Promise<Response> {
  return handleCommandRoute(request, {
    execute: (service, input) => service.createDealDraft(input),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
