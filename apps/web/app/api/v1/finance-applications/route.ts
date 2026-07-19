import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../lib/api/command-route";
import { createM3FinancePaymentsApplicationService } from "../../../../lib/api/postgrest";

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const dealId = url.searchParams.get("deal_id") ?? undefined;
  return handleApplicationQueryRoute(request, {
    createService: createM3FinancePaymentsApplicationService,
    execute: (service, metadata) =>
      service.listFinanceApplications({
        accessToken: metadata.accessToken,
        ...(dealId === undefined ? {} : { dealId }),
        workspaceId: metadata.workspaceId,
      }),
  });
}

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM3FinancePaymentsApplicationService,
    execute: (service, input) => service.createFinanceApplication(input),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
