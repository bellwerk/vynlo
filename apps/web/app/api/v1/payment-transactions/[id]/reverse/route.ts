import { handleApplicationCommandRoute } from "../../../../../../lib/api/command-route";
import { createM3FinancePaymentsApplicationService } from "../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM3FinancePaymentsApplicationService,
    execute: (service, input) =>
      service.reversePaymentTransaction({ ...input, entityId: id }),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
