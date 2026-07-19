import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

/** M4-CFG-AC-002..005, M4-NUM-AC-001: approved, step-up activation only. */
export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) =>
      service.activateNumberingVersion({ ...input, versionId: id }),
    successStatus: () => 200,
  });
}
