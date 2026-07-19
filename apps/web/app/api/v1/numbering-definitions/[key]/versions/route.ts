import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly key: string }>;
}

/** M4-CFG-AC-001, M4-NUM-AC-001: create, validate, and fixture-test a draft. */
export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { key } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) =>
      service.createNumberingVersion({ ...input, definitionKey: key }),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
