import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

/** M4-CALC-AC-002..004, T-CALC-001..002: exact, non-persistent preview. */
export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) => service.runCalculationPreview(input),
    successStatus: () => 200,
  });
}
