import {
  handleApplicationQueryRoute,
  parseStrictQueryParameters,
} from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

export async function GET(request: Request): Promise<Response> {
  return handleApplicationQueryRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, metadata) => {
      const query = new URL(request.url).searchParams;
      parseStrictQueryParameters(request, [
        "cursor_created_at",
        "cursor_id",
        "date_from",
        "date_to",
        "limit",
        "location_id",
      ]);
      const rawLimit = query.get("limit");
      return service.reportInventoryGross(metadata, {
        ...(query.get("cursor_created_at") === null
          ? {}
          : { cursorCreatedAt: query.get("cursor_created_at")! }),
        ...(query.get("cursor_id") === null
          ? {}
          : { cursorId: query.get("cursor_id")! }),
        ...(query.get("date_from") === null
          ? {}
          : { dateFrom: query.get("date_from")! }),
        ...(query.get("date_to") === null
          ? {}
          : { dateTo: query.get("date_to")! }),
        ...(rawLimit === null ? {} : { limit: Number(rawLimit) }),
        ...(query.get("location_id") === null
          ? {}
          : { locationId: query.get("location_id")! }),
      });
    },
  });
}
