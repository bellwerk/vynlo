import { handleApplicationCommandRoute } from "@/lib/api/command-route";
import { createLegalOriginalApplicationService } from "@/lib/api/postgrest";

interface RouteContext {
  readonly params: Promise<{ readonly id: string }>;
}

/** M4-DOC-AC-007, T-DOC-005: append a verified signed-file version. */
export async function POST(
  request: Request,
  context: RouteContext,
): Promise<Response> {
  const { id } = await context.params;
  return handleApplicationCommandRoute(request, {
    createService: createLegalOriginalApplicationService,
    execute: (service, input) =>
      service.createSignedUploadIntent({ ...input, documentId: id }),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
