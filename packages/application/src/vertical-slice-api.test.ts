import { describe, expect, it } from "vitest";
import {
  type AuthenticatedRpcGateway,
  type AuthenticatedRpcRequest,
  VerticalSliceApplicationService,
  VerticalSliceRpcContractError,
  VerticalSliceValidationError,
} from "./vertical-slice-api";

const workspaceId = "00000000-0000-4000-8000-000000000001";
const correlationId = "00000000-0000-4000-8000-000000000002";
const stockDefinitionId = "00000000-0000-4000-8000-000000000003";
const inventoryUnitId = "00000000-0000-4000-8000-000000000004";
const vehicleId = "00000000-0000-4000-8000-000000000005";
const partyId = "00000000-0000-4000-8000-000000000006";
const dealId = "00000000-0000-4000-8000-000000000007";
const participantId = "00000000-0000-4000-8000-000000000008";
const inventoryLinkId = "00000000-0000-4000-8000-000000000009";
const templateVersionId = "00000000-0000-4000-8000-000000000010";
const documentId = "00000000-0000-4000-8000-000000000011";
const outboxEventId = "00000000-0000-4000-8000-000000000012";
const jobId = "00000000-0000-4000-8000-000000000013";

const metadata = Object.freeze({
  accessToken: "header.payload.signature",
  correlationId,
  idempotencyKey: "command-key-0001",
  requestId: "request-0001",
  workspaceId,
});

class RecordingGateway implements AuthenticatedRpcGateway {
  readonly requests: AuthenticatedRpcRequest[] = [];
  response: unknown;

  constructor(response: unknown) {
    this.response = response;
  }

  async invoke(request: AuthenticatedRpcRequest): Promise<unknown> {
    this.requests.push(request);
    return this.response;
  }
}

describe("VerticalSliceApplicationService", () => {
  it("normalizes inventory input and calls the exact RPC contract", async () => {
    const gateway = new RecordingGateway([
      {
        inventory_unit_id: inventoryUnitId,
        replayed: false,
        stock_number: "V0001",
        vehicle_id: vehicleId,
      },
    ]);
    const service = new VerticalSliceApplicationService(gateway);

    await expect(
      service.createInventoryUnit({
        body: {
          acquisitionDate: "2026-07-16",
          advertisedPriceMinor: 1_250_000,
          currencyCode: " cad ",
          make: " Toyota ",
          model: " Corolla ",
          modelYear: 2025,
          odometer: { unit: "km", value: 150 },
          publicNotes: " Ready for sale ",
          stockNumberDefinitionId: stockDefinitionId,
          vin: " 1hgcm82633a004352 ",
        },
        metadata,
      }),
    ).resolves.toEqual({
      inventoryUnitId,
      replayed: false,
      stockNumber: "V0001",
      vehicleId,
    });

    expect(gateway.requests).toEqual([
      {
        accessToken: metadata.accessToken,
        functionName: "create_inventory_unit",
        parameters: {
          p_acquisition_date: "2026-07-16",
          p_advertised_price_minor: 1_250_000,
          p_correlation_id: correlationId,
          p_currency_code: "CAD",
          p_idempotency_key: metadata.idempotencyKey,
          p_make: "Toyota",
          p_model: "Corolla",
          p_model_year: 2025,
          p_odometer_unit: "km",
          p_odometer_value: 150,
          p_public_notes: "Ready for sale",
          p_request_id: metadata.requestId,
          p_stock_definition_id: stockDefinitionId,
          p_vin: "1HGCM82633A004352",
          p_workspace_id: workspaceId,
        },
      },
    ]);
  });

  it("normalizes party input and reports an idempotent replay", async () => {
    const gateway = new RecordingGateway([
      { party_id: partyId, replayed: true },
    ]);
    const service = new VerticalSliceApplicationService(gateway);

    await expect(
      service.createParty({
        body: { displayName: "  Alice   Example  ", partyType: "person" },
        metadata,
      }),
    ).resolves.toEqual({ partyId, replayed: true });
    expect(gateway.requests[0]).toMatchObject({
      functionName: "create_party",
      parameters: {
        p_correlation_id: correlationId,
        p_display_name: "Alice Example",
        p_idempotency_key: metadata.idempotencyKey,
        p_party_type: "person",
        p_request_id: metadata.requestId,
        p_workspace_id: workspaceId,
      },
    });
  });

  it("normalizes the linked deal draft without accepting owner authority", async () => {
    const gateway = new RecordingGateway([
      {
        deal_id: dealId,
        inventory_link_id: inventoryLinkId,
        participant_id: participantId,
        replayed: false,
      },
    ]);
    const service = new VerticalSliceApplicationService(gateway);

    await expect(
      service.createDealDraft({
        body: {
          currencyCode: "cad",
          dealTypeKey: " Retail.Cash ",
          inventory: { inventoryUnitId, roleKey: " Sold " },
          notes: "  New draft  ",
          participant: { partyId, roleKey: " Customer.Primary " },
        },
        metadata,
      }),
    ).resolves.toEqual({
      dealId,
      inventoryLinkId,
      participantId,
      replayed: false,
    });
    expect(gateway.requests[0]).toMatchObject({
      functionName: "create_deal_draft",
      parameters: {
        p_currency_code: "CAD",
        p_deal_type_key: "retail.cash",
        p_inventory_role_key: "sold",
        p_inventory_unit_id: inventoryUnitId,
        p_notes: "New draft",
        p_participant_role_key: "customer.primary",
        p_party_id: partyId,
        p_workspace_id: workspaceId,
      },
    });
  });

  it("calls the atomic document-preview job wrapper and maps its status", async () => {
    const gateway = new RecordingGateway([
      {
        document_id: documentId,
        job_id: jobId,
        job_status: "queued",
        outbox_event_id: outboxEventId,
        preview_status: "queued",
        replayed: false,
        watermark: "DRAFT / NON-PRODUCTION",
      },
    ]);
    const service = new VerticalSliceApplicationService(gateway);

    await expect(
      service.requestDocumentPreview({
        body: { dealId, locale: "en-CA", templateVersionId },
        metadata,
      }),
    ).resolves.toEqual({
      documentId,
      jobId,
      jobStatus: "queued",
      outboxEventId,
      previewStatus: "queued",
      replayed: false,
      watermark: "DRAFT / NON-PRODUCTION",
    });
    expect(gateway.requests[0]).toEqual({
      accessToken: metadata.accessToken,
      functionName: "request_document_preview_job",
      parameters: {
        p_correlation_id: correlationId,
        p_deal_id: dealId,
        p_idempotency_key: metadata.idempotencyKey,
        p_locale: "en-CA",
        p_request_id: metadata.requestId,
        p_template_version_id: templateVersionId,
        p_workspace_id: workspaceId,
      },
    });
  });

  it.each([
    ["inventory", { vin: "1HGCM82633A004352", workspaceId }],
    [
      "party",
      { displayName: "Alice", partyType: "person", workspace_id: workspaceId },
    ],
    [
      "deal",
      { currencyCode: "CAD", dealTypeKey: "retail.cash", ownerUserId: partyId },
    ],
    ["preview", { dealId, locale: "en-CA", templateVersionId, workspaceId }],
  ])(
    "rejects %s workspace or owner spoof fields before RPC",
    async (kind, body) => {
      const gateway = new RecordingGateway([]);
      const service = new VerticalSliceApplicationService(gateway);
      const operation =
        kind === "inventory"
          ? service.createInventoryUnit({ body, metadata })
          : kind === "party"
            ? service.createParty({ body, metadata })
            : kind === "deal"
              ? service.createDealDraft({ body, metadata })
              : service.requestDocumentPreview({ body, metadata });

      await expect(operation).rejects.toMatchObject({
        code: "invalid_request_body",
      });
      expect(gateway.requests).toEqual([]);
    },
  );

  it("reports domain normalization errors without invoking PostgREST", async () => {
    const gateway = new RecordingGateway([]);
    const service = new VerticalSliceApplicationService(gateway);
    const error = await service
      .createInventoryUnit({
        body: {
          acquisitionDate: null,
          advertisedPriceMinor: null,
          currencyCode: "CAD",
          make: null,
          model: null,
          modelYear: null,
          odometer: null,
          publicNotes: null,
          stockNumberDefinitionId: stockDefinitionId,
          vin: "INVALIDVIN",
        },
        metadata,
      })
      .catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(VerticalSliceValidationError);
    expect(error).toMatchObject({ code: "invalid_vin" });
    expect(gateway.requests).toEqual([]);
  });

  it("fails closed when PostgREST returns missing or unexpected fields", async () => {
    const gateway = new RecordingGateway([
      { party_id: partyId, replayed: false, secret: "must-not-be-accepted" },
    ]);
    const service = new VerticalSliceApplicationService(gateway);

    await expect(
      service.createParty({
        body: { displayName: "Alice", partyType: "person" },
        metadata,
      }),
    ).rejects.toBeInstanceOf(VerticalSliceRpcContractError);
  });
});
