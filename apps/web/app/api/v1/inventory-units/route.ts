import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../lib/api/command-route";
import {
  createM2CostSearchApplicationService,
  createVinInventoryIntakeApplicationService,
} from "../../../../lib/api/postgrest";

function numberParameter(value: string | null): number | undefined {
  return value === null ? undefined : Number(value);
}

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const cursorId = url.searchParams.get("cursor_id");
  const cursorRank = url.searchParams.get("cursor_rank");
  const cursorUpdatedAt = url.searchParams.get("cursor_updated_at");
  const cursorRequested =
    cursorId !== null || cursorRank !== null || cursorUpdatedAt !== null;

  return handleApplicationQueryRoute(request, {
    createService: createM2CostSearchApplicationService,
    execute: (service, metadata) =>
      service.search({
        accessToken: metadata.accessToken,
        query: {
          cursor: cursorRequested
            ? {
                id: cursorId,
                rank: Number(cursorRank),
                updatedAt: cursorUpdatedAt,
              }
            : null,
          locationIds: url.searchParams.getAll("location_id"),
          maximumDaysInStock: numberParameter(
            url.searchParams.get("maximum_days_in_stock"),
          ),
          maximumPriceMinor: url.searchParams.get("maximum_price_minor"),
          minimumDaysInStock: numberParameter(
            url.searchParams.get("minimum_days_in_stock"),
          ),
          minimumPriceMinor: url.searchParams.get("minimum_price_minor"),
          pageSize: numberParameter(url.searchParams.get("page_size")),
          query: url.searchParams.get("q"),
          statuses: url.searchParams.getAll("status"),
        },
        workspaceId: metadata.workspaceId,
      }),
  });
}

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createVinInventoryIntakeApplicationService,
    execute: (service, input) => service.createFromConfirmedDecode(input),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
