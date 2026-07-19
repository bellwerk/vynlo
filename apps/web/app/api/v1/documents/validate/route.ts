import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

/** M4-DOC-AC-001..004: validate exact activation gates without mutation. */
export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) => service.validateDocument(input),
    successStatus: () => 200,
  });
}
