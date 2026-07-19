import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../../lib/api/command-route";
import { createM3FinancePaymentsApplicationService } from "../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM3FinancePaymentsApplicationService,
    execute: (service, metadata) =>
      service.getFinanceApplication({
        accessToken: metadata.accessToken,
        financeApplicationId: id,
        workspaceId: metadata.workspaceId,
      }),
  });
}

export async function PATCH(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM3FinancePaymentsApplicationService,
    execute: (service, input) =>
      service.updateFinanceApplication({ ...input, entityId: id }),
    successStatus: () => 200,
  });
}
