import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../../../lib/api/command-route";
import { createM2CostSearchApplicationService } from "../../../../../../lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

function ledgerQuery(request: Request): unknown {
  const parameters = new URL(request.url).searchParams;
  const createdAt = parameters.get("beforeCreatedAt");
  const id = parameters.get("beforeId");
  const pageSize = parameters.get("pageSize");
  return {
    cursor: createdAt === null && id === null ? null : { createdAt, id },
    pageSize: pageSize === null ? 100 : Number(pageSize),
  };
}

export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM2CostSearchApplicationService,
    execute: (service, metadata) =>
      service.getCosts({
        accessToken: metadata.accessToken,
        entityId: id,
        query: ledgerQuery(request),
        workspaceId: metadata.workspaceId,
      }),
  });
}

export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createM2CostSearchApplicationService,
    execute: (service, input) => service.postCost({ ...input, entityId: id }),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
