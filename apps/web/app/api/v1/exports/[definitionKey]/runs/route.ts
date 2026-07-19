import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly definitionKey: string }>;
}

/** M4-EXP-AC-001..004, T-EXP-001..002: queue an authorized immutable run. */
export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { definitionKey } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) =>
      service.requestExportRun({ ...input, definitionKey }),
    successStatus: (result) => (result.replayed ? 200 : 202),
  });
}
