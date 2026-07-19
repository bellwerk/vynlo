import { handleApplicationQueryRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

/** M4-EXP-AC-001..005: list only available, authorized export versions. */
export async function GET(request: Request): Promise<Response> {
  return handleApplicationQueryRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, metadata) => service.listExportDefinitions(metadata),
  });
}
