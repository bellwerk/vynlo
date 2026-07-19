import { handleApplicationCommandRoute } from "../../../../../lib/api/command-route";
import {
  createM4ApplicationService,
  createVerticalSliceApplicationService,
} from "../../../../../lib/api/postgrest";

function isM4PreviewBody(body: unknown): boolean {
  return (
    typeof body === "object" &&
    body !== null &&
    !Array.isArray(body) &&
    "documentTypeId" in body
  );
}

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: () => ({
      legacy: createVerticalSliceApplicationService(),
      m4: createM4ApplicationService(),
    }),
    execute: async (service, input) =>
      isM4PreviewBody(input.body)
        ? await service.m4.requestDocumentPreview(input)
        : await service.legacy.requestDocumentPreview(input),
    successStatus: (result) => (result.replayed ? 200 : 202),
  });
}
