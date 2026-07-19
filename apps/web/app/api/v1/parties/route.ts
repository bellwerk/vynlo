import {
  handleApplicationCommandRoute,
  handleApplicationQueryRoute,
} from "../../../../lib/api/command-route";
import {
  createM3CrmApplicationService,
  createVerticalSliceApplicationService,
} from "../../../../lib/api/postgrest";

function isLegacyPartyBody(body: unknown): boolean {
  return (
    typeof body === "object" &&
    body !== null &&
    !Array.isArray(body) &&
    !("preferredLocale" in body)
  );
}

export async function GET(request: Request): Promise<Response> {
  return handleApplicationQueryRoute(request, {
    createService: createM3CrmApplicationService,
    execute: (service, metadata) =>
      service.listParties({
        accessToken: metadata.accessToken,
        workspaceId: metadata.workspaceId,
      }),
  });
}

export async function POST(request: Request): Promise<Response> {
  return handleApplicationCommandRoute(request, {
    createService: () => ({
      legacy: createVerticalSliceApplicationService(),
      m3: createM3CrmApplicationService(),
    }),
    execute: (service, input) =>
      isLegacyPartyBody(input.body)
        ? service.legacy.createParty(input)
        : service.m3.createParty(input),
    successStatus: (result) => (result.replayed ? 200 : 201),
  });
}
