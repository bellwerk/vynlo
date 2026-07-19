import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

/** M4-DOC-AC-004..006, M4-NUM-AC-002..005, T-DOC-002, T-NUM-001..003. */
export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) => service.requestOfficialDocument(input),
    successStatus: (result) => (result.replayed ? 200 : 202),
  });
}
