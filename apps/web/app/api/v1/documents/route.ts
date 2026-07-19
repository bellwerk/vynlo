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
        "deal_id",
        "document_type_key",
        "limit",
        "mode",
        "status",
      ]);
      const rawLimit = query.get("limit");
      return service.listDocuments(metadata, {
        ...(query.get("cursor_created_at") === null
          ? {}
          : { cursorCreatedAt: query.get("cursor_created_at")! }),
        ...(query.get("cursor_id") === null
          ? {}
          : { cursorId: query.get("cursor_id")! }),
        ...(query.get("deal_id") === null
          ? {}
          : { dealId: query.get("deal_id")! }),
        ...(query.get("document_type_key") === null
          ? {}
          : { documentTypeKey: query.get("document_type_key")! }),
        ...(rawLimit === null ? {} : { limit: Number(rawLimit) }),
        ...(query.get("mode") === null ? {} : { mode: query.get("mode")! }),
        ...(query.get("status") === null
          ? {}
          : { status: query.get("status")! }),
      });
    },
  });
}
