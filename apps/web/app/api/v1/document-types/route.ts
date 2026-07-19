import { handleApplicationQueryRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

/** M4-DOC-AC-001, T-DOC-001: workspace-scoped document availability. */
export async function GET(request: Request): Promise<Response> {
  return handleApplicationQueryRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, metadata) => service.listDocumentTypes(metadata),
  });
}
