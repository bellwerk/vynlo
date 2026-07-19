import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

/** M4-DOC-AC-006, M4-NUM-AC-003: retry the same snapshot and number. */
export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) =>
      service.retryDocumentRender({ ...input, documentId: id }),
    successStatus: (result) => (result.replayed ? 200 : 202),
  });
}
