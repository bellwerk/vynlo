import { handleApplicationCommandRoute } from "../../../../../../../lib/api/command-route";
import { createM3FinancePaymentsApplicationService } from "../../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{
    readonly conditionId: string;
    readonly id: string;
  }>;
}

export async function PATCH(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { conditionId, id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM3FinancePaymentsApplicationService,
    execute: (service, input) =>
      service.updateFinanceCondition({
        ...input,
        conditionId,
        entityId: id,
      }),
    successStatus: () => 200,
  });
}
