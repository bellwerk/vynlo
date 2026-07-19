import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

/** M4-CALC-AC-001..003, T-CALC-001: reject unsafe or invalid ASTs. */
export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) => service.validateCalculation(input),
    successStatus: () => 200,
  });
}
