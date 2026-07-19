import { handleApplicationQueryRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

/** M4-TAX-AC-001..005, T-TAX-001: list packs and exact version gates. */
export async function GET(request: Request): Promise<Response> {
  return handleApplicationQueryRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, metadata) => service.listTaxPacks(metadata),
  });
}
