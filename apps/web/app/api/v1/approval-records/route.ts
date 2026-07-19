import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
  parseStrictQueryParameters,
} from "@/lib/api/command-route";
import { createM4ApplicationService } from "@/lib/api/postgrest";

/** M4-CFG-AC-005: exact-version, append-only approval evidence. */
export async function GET(request: Request): Promise<Response> {
  return handleApplicationQueryRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, metadata) => {
      const query = new URL(request.url).searchParams;
      parseStrictQueryParameters(request, [
        "artifact_key",
        "artifact_type",
        "current_only",
        "cursor_created_at",
        "cursor_id",
        "limit",
      ]);
      const rawCurrentOnly = query.get("current_only");
      const rawLimit = query.get("limit");
      return service.listApprovalRecords(metadata, {
        ...(query.get("artifact_key") === null
          ? {}
          : { artifactKey: query.get("artifact_key")! }),
        ...(query.get("artifact_type") === null
          ? {}
          : { artifactType: query.get("artifact_type")! }),
        ...(query.get("cursor_created_at") === null
          ? {}
          : { cursorCreatedAt: query.get("cursor_created_at")! }),
        ...(query.get("cursor_id") === null
          ? {}
          : { cursorId: query.get("cursor_id")! }),
        ...(rawCurrentOnly === null
          ? {}
          : {
              currentOnly:
                rawCurrentOnly === "true"
                  ? true
                  : rawCurrentOnly === "false"
                    ? false
                    : rawCurrentOnly,
            }),
        ...(rawLimit === null ? {} : { limit: Number(rawLimit) }),
      });
    },
  });
}

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: createM4ApplicationService,
    execute: (service, input) => service.createApprovalRecord(input),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
