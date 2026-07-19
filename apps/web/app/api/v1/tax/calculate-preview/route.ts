import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

/** M4-TAX-AC-001..004, T-TAX-001..002: explicit, non-persistent selection. */
export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) => service.runTaxPreview(input),
    successStatus: () => 200,
  });
}
