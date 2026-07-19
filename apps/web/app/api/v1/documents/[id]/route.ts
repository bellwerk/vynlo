import { handleApplicationQueryRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

/** M4-DOC-AC-005..009: immutable versions, files, job state, and lineage. */
export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, metadata) => service.getDocument(metadata, id),
  });
}
