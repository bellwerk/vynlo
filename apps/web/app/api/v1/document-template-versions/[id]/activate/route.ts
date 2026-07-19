import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

/** M4-CFG-AC-001/002/005, M4-DOC-AC-001/004: activate one exact imported template. */
export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) =>
      service.activateDocumentTemplateVersion({
        ...input,
        templateVersionId: id,
      }),
    successStatus: () => 200,
  });
}
