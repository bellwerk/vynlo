import { handleApplicationQueryRoute } from "@/lib/api/command-route";
import { createM4DownloadApplicationService } from "@/lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly fileId: string; readonly id: string }>;
}

/** M4-DOC-AC-010: authorize, re-verify immutable bytes, then sign briefly. */
export async function GET(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { fileId, id } = await context.params;
  return handleApplicationQueryRoute(request, {
    createService: createM4DownloadApplicationService,
    execute: (service, metadata) =>
      service.authorizeDocumentFileDownload(metadata, id, fileId),
  });
}
