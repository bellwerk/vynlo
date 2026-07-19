import { handleApplicationQueryRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

/** M4-NUM-AC-001, T-NUM-001: list immutable numbering versions. */
export async function GET(request: Request): Promise<Response> {
  return handleApplicationQueryRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, metadata) => service.listNumberingDefinitions(metadata),
  });
}
