// Stable test IDs: T-CALC-001, T-TAX-001, T-API-001.
import { describe, expect, it, vi } from "vitest";
import {
  CALCULATION_ENGINE_VERSION,
  canonicalJson,
  compileCalculationDefinition,
  sha256Hex,
  type CalculationJson,
} from "@vynlo/calculations";
import { TAX_ENGINE_VERSION, compileTaxPack } from "@vynlo/tax";

import type { AuthenticatedRpcGateway } from "./vertical-slice-api";
import {
  M4ApplicationService,
  M4ApplicationValidationError,
  M4RpcContractError,
  M4_RPC,
} from "./m4-api";

const workspaceId = "00000000-0000-4000-8000-000000000001";
const dealId = "00000000-0000-4000-8000-000000000002";
const documentTypeId = "00000000-0000-4000-8000-000000000003";
const templateVersionId = "00000000-0000-4000-8000-000000000004";
const documentId = "00000000-0000-4000-8000-000000000005";
const jobId = "00000000-0000-4000-8000-000000000006";
const outboxEventId = "00000000-0000-4000-8000-000000000007";
const auditEventId = "00000000-0000-4000-8000-000000000008";
const numberAllocationId = "00000000-0000-4000-8000-000000000009";
const calculationVersionId = "00000000-0000-4000-8000-000000000013";
const taxPackVersionId = "00000000-0000-4000-8000-000000000014";
const calculationEvidenceId = "00000000-0000-4000-8000-000000000015";
const taxEvidenceId = "00000000-0000-4000-8000-000000000016";

const metadata = Object.freeze({
  accessToken: "header.payload.signature",
  correlationId: "00000000-0000-4000-8000-000000000010",
  idempotencyKey: "m4-official-0001",
  requestId: "m4-test-request",
  workspaceId,
});

const officialBody = Object.freeze({
  calculationEvidence: null,
  dealId,
  documentDate: "2026-07-16",
  documentFields: { purchaser_name: "Synthetic Person" },
  documentTypeId,
  intendedSignatureDate: null,
  locale: "en-CA",
  reason: "Generate approved synthetic fixture document.",
  taxEvidence: null,
  templateVersionId,
});

function gatewayReturning(value: unknown) {
  const invoke = vi
    .fn<AuthenticatedRpcGateway["invoke"]>()
    .mockResolvedValue(value);
  return { gateway: { invoke }, invoke };
}

function checksumWithout(
  value: Readonly<Record<string, unknown>>,
  excludedKeys: readonly string[],
): string {
  const projection = { ...value };
  for (const key of excludedKeys) delete projection[key];
  return sha256Hex(canonicalJson(projection as CalculationJson));
}

describe("M4 application API", () => {
  it("maps document type and template activation to the generic exact artifact lifecycle", async () => {
    const { gateway, invoke } = gatewayReturning([
      {
        approval_record_id: "00000000-0000-4000-8000-000000000017",
        artifact_id: documentTypeId,
        artifact_status: "active",
        audit_event_id: auditEventId,
        replayed: false,
      },
    ]);
    const service = new M4ApplicationService({ gateway });
    const body = {
      expectedChecksum: "a".repeat(64),
      expectedVersion: 1,
      reason: "Activate exact imported document configuration.",
    };

    await service.activateDocumentType({
      body,
      documentTypeId,
      metadata,
    });
    await service.activateDocumentTemplateVersion({
      body,
      metadata: { ...metadata, idempotencyKey: "m4-template-activate-0001" },
      templateVersionId,
    });

    expect(invoke).toHaveBeenNthCalledWith(1, {
      accessToken: metadata.accessToken,
      functionName: M4_RPC.activateDocumentType,
      parameters: expect.objectContaining({
        p_artifact_id: documentTypeId,
        p_artifact_type: "document_type",
        p_target_status: "active",
      }),
    });
    expect(invoke).toHaveBeenNthCalledWith(2, {
      accessToken: metadata.accessToken,
      functionName: M4_RPC.activateDocumentTemplateVersion,
      parameters: expect.objectContaining({
        p_artifact_id: templateVersionId,
        p_artifact_type: "document_template",
        p_target_status: "active",
      }),
    });
  });

  it("derives workspace context and maps the official command to the one canonical RPC", async () => {
    const { gateway, invoke } = gatewayReturning([
      {
        aggregate_version: 1,
        audit_event_id: auditEventId,
        document_id: documentId,
        document_status: "generating",
        job_id: jobId,
        number_allocation_id: numberAllocationId,
        official_number: "SYN-000001",
        outbox_event_id: outboxEventId,
        replayed: false,
      },
    ]);
    const service = new M4ApplicationService({ gateway });

    await expect(
      service.requestOfficialDocument({ body: officialBody, metadata }),
    ).resolves.toMatchObject({
      document_id: documentId,
      official_number: "SYN-000001",
    });
    expect(invoke).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      functionName: M4_RPC.requestOfficialDocument,
      parameters: expect.objectContaining({
        p_deal_id: dealId,
        p_idempotency_key: metadata.idempotencyKey,
        p_supersedes_document_id: null,
        p_supersedes_expected_version: null,
        p_workspace_id: workspaceId,
      }),
    });
  });

  it("requires and forwards the current aggregate version only for supersession", async () => {
    const { gateway, invoke } = gatewayReturning([
      {
        aggregate_version: 1,
        audit_event_id: auditEventId,
        document_id: "00000000-0000-4000-8000-000000000019",
        document_status: "generating",
        job_id: jobId,
        number_allocation_id: numberAllocationId,
        official_number: "SYN-000002",
        outbox_event_id: outboxEventId,
        replayed: false,
      },
    ]);
    const service = new M4ApplicationService({ gateway });

    await expect(
      service.supersedeDocument({
        body: { ...officialBody, expectedVersion: 7 },
        documentId,
        metadata,
      }),
    ).resolves.toMatchObject({ official_number: "SYN-000002" });
    expect(invoke).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      functionName: M4_RPC.requestOfficialDocument,
      parameters: expect.objectContaining({
        p_supersedes_document_id: documentId,
        p_supersedes_expected_version: 7,
      }),
    });

    expect(() =>
      service.supersedeDocument({
        body: officialBody,
        documentId,
        metadata,
      }),
    ).toThrow(M4ApplicationValidationError);
    expect(invoke).toHaveBeenCalledTimes(1);
  });

  it("uses the existing audited void command to recover a failed replacement", async () => {
    const voidedAt = "2026-07-16T12:30:00.000Z";
    const { gateway, invoke } = gatewayReturning([
      {
        aggregate_version: 4,
        audit_event_id: auditEventId,
        document_id: documentId,
        document_status: "voided",
        replayed: false,
        voided_at: voidedAt,
      },
    ]);
    const service = new M4ApplicationService({ gateway });

    await expect(
      service.voidDocument({
        body: {
          expectedVersion: 3,
          reason: "Abandon failed replacement and preserve its evidence.",
        },
        documentId,
        metadata,
      }),
    ).resolves.toMatchObject({
      document_status: "voided",
      voided_at: voidedAt,
    });
    expect(invoke).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      functionName: M4_RPC.voidDocument,
      parameters: expect.objectContaining({
        p_document_id: documentId,
        p_expected_version: 3,
        p_workspace_id: workspaceId,
      }),
    });
  });

  it("rejects an official number supplied by the client", async () => {
    const { gateway, invoke } = gatewayReturning([]);
    const service = new M4ApplicationService({ gateway });

    expect(() =>
      service.requestOfficialDocument({
        body: { ...officialBody, officialNumber: "CLIENT-1" },
        metadata,
      }),
    ).toThrow(M4ApplicationValidationError);
    expect(invoke).not.toHaveBeenCalled();
  });

  it("rejects a data-store response with an unrecognized lifecycle state", async () => {
    const { gateway } = gatewayReturning([
      {
        aggregate_version: 1,
        audit_event_id: auditEventId,
        document_id: documentId,
        document_status: "almost_done",
        job_id: jobId,
        number_allocation_id: numberAllocationId,
        official_number: "SYN-000001",
        outbox_event_id: outboxEventId,
        replayed: false,
      },
    ]);
    const service = new M4ApplicationService({ gateway });

    await expect(
      service.requestOfficialDocument({ body: officialBody, metadata }),
    ).rejects.toBeInstanceOf(M4RpcContractError);
  });

  it("accepts preview artifact identity and the exact official failure/file contracts", async () => {
    const previewArtifactId = "00000000-0000-4000-8000-000000000017";
    const fileId = "00000000-0000-4000-8000-000000000018";
    const { gateway } = gatewayReturning([
      {
        aggregate_version: 2,
        calculation_snapshot: null,
        created_at: "2026-07-16T12:00:00Z",
        current_file_id: fileId,
        deal_id: dealId,
        document_date: "2026-07-16",
        document_type_key: "fixture.official",
        files: [
          {
            byte_size: 512,
            checksum_sha256: "b".repeat(64),
            created_at: "2026-07-16T12:01:00Z",
            current: true,
            filename: "signed.pdf",
            id: fileId,
            mime_type: "application/pdf",
            role: "signed_scan",
            version: 1,
          },
        ],
        generated_at: null,
        id: documentId,
        intended_signature_date: null,
        job_status: "dead_letter",
        jobs: [
          {
            attempt_count: 3,
            failure_code: "fixture.render_failed",
            job_id: jobId,
            review_required: true,
            status: "dead_letter",
            updated_at: "2026-07-16T12:02:00Z",
          },
        ],
        locale: "en-CA",
        mode: "official",
        official_number: "SYN-000001",
        preview_artifact_id: previewArtifactId,
        render_input_checksum: "c".repeat(64),
        signed_at: null,
        status: "generation_failed",
        superseded_by_document_id: null,
        supersedes_document_id: null,
        tax_snapshot: null,
        version_snapshot: { schemaVersion: 2 },
        version_snapshot_checksum: "d".repeat(64),
        void_reason: null,
      },
    ]);
    const service = new M4ApplicationService({ gateway });

    await expect(
      service.getDocument(metadata, documentId),
    ).resolves.toMatchObject({
      files: [{ role: "signed_scan" }],
      jobs: [{ review_required: true, status: "dead_letter" }],
      preview_artifact_id: previewArtifactId,
      status: "generation_failed",
    });
  });

  it("rejects partial keyset cursors before calling a report RPC", async () => {
    const { gateway, invoke } = gatewayReturning([]);
    const service = new M4ApplicationService({ gateway });

    expect(() =>
      service.reportDeals(metadata, {
        cursorCreatedAt: "2026-07-16T12:00:00Z",
        limit: 25,
      }),
    ).toThrow(M4ApplicationValidationError);
    expect(invoke).not.toHaveBeenCalled();
  });

  it("refuses a download authorization for a different owning document", async () => {
    const otherDocumentId = "00000000-0000-4000-8000-000000000099";
    const fileId = "00000000-0000-4000-8000-000000000011";
    const { gateway } = gatewayReturning([
      {
        authorization_expires_at: "2026-07-16T12:05:00Z",
        authorization_id: "00000000-0000-4000-8000-000000000012",
        audit_event_id: auditEventId,
        byte_size: 123,
        checksum_sha256: "a".repeat(64),
        document_file_id: fileId,
        document_id: otherDocumentId,
        filename: "official.pdf",
        mime_type: "application/pdf",
        replayed: false,
      },
    ]);
    const issue = vi.fn().mockResolvedValue({
      expiresAt: "2026-07-16T12:05:00Z",
      url: "https://storage.invalid/signed",
    });
    const service = new M4ApplicationService({
      downloadGrants: { issue },
      gateway,
    });

    await expect(
      service.authorizeDocumentFileDownload(metadata, documentId, fileId),
    ).rejects.toBeInstanceOf(M4RpcContractError);
    expect(issue).not.toHaveBeenCalled();
  });

  it("loads calculation configuration, executes the domain runtime, and returns canonical evidence", async () => {
    const definition = {
      approval_refs: ["approval-fixture"],
      fixtures: ["fixture/sale-total.json"],
      input_schema: {},
      key: "sale-total",
      outputs: {
        total_minor: {
          args: [
            { op: "field", path: "vehicle_price_minor" },
            { op: "field", path: "taxable_fees_minor" },
          ],
          op: "add",
        },
      },
      rounding: { currency: "CAD", minor_unit: 2, mode: "half_up" },
      status: "active",
      version: "1.0.0",
    };
    compileCalculationDefinition(definition);
    const definitionChecksum = checksumWithout(definition, [
      "approval_refs",
      "status",
    ]);
    const { gateway, invoke } = gatewayReturning([
      {
        calculation_version_id: calculationVersionId,
        definition,
        definition_checksum: definitionChecksum,
        engine_version: CALCULATION_ENGINE_VERSION,
        resource_limits: {},
      },
    ]);
    const record = vi
      .fn()
      .mockResolvedValue({ evidenceId: calculationEvidenceId });
    const service = new M4ApplicationService({
      gateway,
      runtimeEvidence: { record },
    });

    const evidence = await service.runCalculationPreview({
      body: {
        calculationVersionId,
        inputs: {
          taxable_fees_minor: "500",
          vehicle_price_minor: "10000",
        },
      },
      metadata,
    });
    const { checksum, evidenceId, ...withoutChecksum } = evidence;

    expect(evidenceId).toBe(calculationEvidenceId);
    expect(evidence.definition).toEqual(definition);
    expect(evidence.definitionChecksum).toBe(definitionChecksum);
    expect(evidence.definitionKey).toBe("sale-total");
    expect(evidence.definitionVersion).toBe("1.0.0");
    expect(evidence.output).toEqual({ total_minor: "10500" });
    expect(checksum).toBe(
      sha256Hex(canonicalJson(withoutChecksum as CalculationJson)),
    );
    expect(invoke).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      functionName: M4_RPC.loadCalculationPreviewConfiguration,
      parameters: {
        p_calculation_version_id: calculationVersionId,
        p_workspace_id: workspaceId,
      },
    });
    expect(record).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      assignmentId: null,
      correlationId: metadata.correlationId,
      dealId: null,
      evidence: expect.objectContaining({
        checksum,
        definition,
        versionId: calculationVersionId,
      }),
      idempotencyKey: metadata.idempotencyKey,
      kind: "calculation",
      requestId: metadata.requestId,
      versionId: calculationVersionId,
      workspaceId,
    });

    const serviceWithoutRecorder = new M4ApplicationService({ gateway });
    await expect(
      serviceWithoutRecorder.runCalculationPreview({
        body: {
          calculationVersionId,
          inputs: {
            taxable_fees_minor: "500",
            vehicle_price_minor: "10000",
          },
        },
        metadata,
      }),
    ).rejects.toBeInstanceOf(M4RpcContractError);
  });

  it("replaces client calculation inputs with the checksum-verified deal projection", async () => {
    const definition = {
      approval_refs: ["approval-fixture"],
      fixtures: ["fixture/deal.json"],
      input_schema: {},
      key: "deal-total",
      outputs: { deal_version: { op: "field", path: "deal.version" } },
      rounding: { currency: "CAD", minor_unit: 2, mode: "half_up" },
      status: "active",
      version: "1.0.0",
    };
    const canonicalInput = {
      deal: { currency_code: "CAD", id: dealId, version: 7 },
      inventory_units: [],
      line_items: [],
      participants: [],
      schema_version: 4,
      trade_ins: [],
    };
    const definitionChecksum = checksumWithout(definition, [
      "approval_refs",
      "status",
    ]);
    const inputChecksum = sha256Hex(
      canonicalJson(canonicalInput as CalculationJson),
    );
    const invoke = vi
      .fn<AuthenticatedRpcGateway["invoke"]>()
      .mockResolvedValueOnce([
        {
          calculation_version_id: calculationVersionId,
          definition,
          definition_checksum: definitionChecksum,
          engine_version: CALCULATION_ENGINE_VERSION,
          resource_limits: {},
        },
      ])
      .mockResolvedValueOnce([
        {
          calculation_input: canonicalInput,
          calculation_input_checksum: inputChecksum,
          deal_context_checksum: inputChecksum,
          deal_currency_code: "CAD",
          tax_input: null,
          tax_input_checksum: null,
        },
      ]);
    const record = vi
      .fn()
      .mockResolvedValue({ evidenceId: calculationEvidenceId });
    const service = new M4ApplicationService({
      gateway: { invoke },
      runtimeEvidence: { record },
    });

    const evidence = await service.runCalculationPreview({
      body: {
        calculationVersionId,
        dealId,
        inputs: { deal: { version: 999 } },
      },
      metadata,
    });

    expect(evidence.input).toEqual(canonicalInput);
    expect(evidence.output).toEqual({ deal_version: "7" });
    expect(evidence.inputBinding).toEqual({
      dealContextChecksum: inputChecksum,
      inputProjectionChecksum: inputChecksum,
      mapperVersion: "deal-runtime-input-v1",
    });
    expect(invoke).toHaveBeenNthCalledWith(2, {
      accessToken: metadata.accessToken,
      functionName: M4_RPC.loadDealRuntimeInput,
      parameters: {
        p_deal_id: dealId,
        p_jurisdiction_code: null,
        p_workspace_id: workspaceId,
      },
    });
    expect(record).toHaveBeenCalledWith(
      expect.objectContaining({
        dealId,
        evidence: expect.objectContaining({ input: canonicalInput }),
      }),
    );
  });

  it("validates calculation ASTs locally without a business-logic RPC", async () => {
    const { gateway, invoke } = gatewayReturning([]);
    const service = new M4ApplicationService({ gateway });

    await expect(
      service.validateCalculation({
        body: {
          definition: {
            fixtures: ["fixture/unsafe.json"],
            input_schema: {},
            key: "unsafe-definition",
            outputs: { result: { op: "tenant_javascript" } },
            rounding: {},
            status: "draft",
            version: "1.0.0",
          },
        },
        metadata,
      }),
    ).resolves.toMatchObject({
      checksum: null,
      errors: ["unknown_operation"],
      valid: false,
    });
    expect(invoke).not.toHaveBeenCalled();
  });

  it("loads one tax candidate, executes the tax runtime, and keeps candidate evidence non-official", async () => {
    const definition = {
      activation_status: "draft",
      approval_refs: [],
      contexts: ["vehicle_retail_sale"],
      effective_from: "2026-01-01",
      effective_to: null,
      golden_tests: ["tests/basic.json"],
      jurisdiction: "CA-QC",
      key: "tax-ca-qc",
      rules: {
        currency: "CAD",
        rounding: {
          mode: "HALF_UP",
          scale: 2,
          stage: "tax_total_per_tax_type",
        },
        taxes: [
          {
            key: "gst",
            labels: { en: "GST", fr: "TPS" },
            rate: "0.05",
            source_ref: "authority",
            taxable_base: "eligible_taxable_consideration",
          },
        ],
        trade_in: {
          lien_payoff_is_not_automatically_tax_credit: true,
          requires_explicit_eligibility_inputs: true,
          strategy: "conditional_credit_reduces_taxable_consideration",
        },
        unsupported_without_override: [],
      },
      sources: [
        {
          accessed_on: "2026-01-01",
          authority: "Synthetic tax authority",
          key: "authority",
          url: "https://example.invalid/tax",
        },
      ],
      version: "1.0.0",
    };
    compileTaxPack(definition);
    const definitionChecksum = checksumWithout(definition, [
      "activation_status",
      "approval_refs",
    ]);
    const { gateway, invoke } = gatewayReturning([
      {
        assignment_id: null,
        definition,
        definition_checksum: definitionChecksum,
        engine_version: TAX_ENGINE_VERSION,
        override_authorized: false,
        tax_pack_version_id: taxPackVersionId,
      },
    ]);
    const record = vi.fn().mockResolvedValue({ evidenceId: taxEvidenceId });
    const service = new M4ApplicationService({
      gateway,
      runtimeEvidence: { record },
    });

    const evidence = await service.runTaxPreview({
      body: {
        contextKey: "vehicle_retail_sale",
        currencyCode: "CAD",
        inputs: { vehicle_price_minor: "10000" },
        jurisdictionCode: "CA-QC",
        override: null,
        overrideReason: null,
        transactionDate: "2026-07-16",
      },
      metadata,
    });
    const { checksum, evidenceId, ...withoutChecksum } = evidence;

    expect(evidence.assignmentId).toBeNull();
    expect(evidenceId).toBe(taxEvidenceId);
    expect(evidence.pack).toEqual(definition);
    expect(evidence.packChecksum).toBe(definitionChecksum);
    expect(evidence.packKey).toBe("tax-ca-qc");
    expect(evidence.packVersion).toBe("1.0.0");
    expect(evidence.output.total_tax_minor).toBe("500");
    expect(checksum).toBe(
      sha256Hex(canonicalJson(withoutChecksum as CalculationJson)),
    );
    expect(invoke).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      functionName: M4_RPC.loadTaxPreviewConfiguration,
      parameters: expect.objectContaining({
        p_context_key: "vehicle_retail_sale",
        p_override_requested: false,
        p_workspace_id: workspaceId,
      }),
    });
    expect(record).toHaveBeenCalledWith({
      accessToken: metadata.accessToken,
      assignmentId: null,
      correlationId: metadata.correlationId,
      dealId: null,
      evidence: expect.objectContaining({
        checksum,
        pack: definition,
        versionId: taxPackVersionId,
      }),
      idempotencyKey: metadata.idempotencyKey,
      kind: "tax",
      requestId: metadata.requestId,
      versionId: taxPackVersionId,
      workspaceId,
    });
  });
});
