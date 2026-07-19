import {
  computeDocumentTemplateVersionChecksum,
  computeDocumentTypeVersionChecksum,
  type DocumentApprovalRecord,
  type DocumentConfigurationStatus,
  type DocumentTemplateVersion,
  type DocumentTemplateVersionPayload,
  type DocumentTypeVersion,
  type DocumentTypeVersionPayload,
  type ImmutableVersionReference,
} from "./configuration";
import { checksumJson, sha256Hex } from "./domain-common";
import {
  computeNumberingDefinitionChecksum,
  type NumberingDefinitionPayload,
  type NumberingVersionStatus,
  type VersionedNumberingDefinition,
} from "./numbering";
import {
  computeTemplateSourceBundleChecksum,
  type DocumentTemplateSourceBundle,
} from "./template-runtime";

export const M4_TEST_IDS = Object.freeze({
  allocation: "14000000-0000-4000-8000-000000000001",
  allocationReplacement: "14000000-0000-4000-8000-000000000002",
  approvalDocument: "15000000-0000-4000-8000-000000000001",
  approvalNumbering: "15000000-0000-4000-8000-000000000003",
  approvalTemplate: "15000000-0000-4000-8000-000000000002",
  document: "16000000-0000-4000-8000-000000000001",
  documentReplacement: "16000000-0000-4000-8000-000000000002",
  documentType: "11000000-0000-4000-8000-000000000001",
  fileGenerated: "17000000-0000-4000-8000-000000000001",
  fileSignedOne: "17000000-0000-4000-8000-000000000002",
  fileSignedTwo: "17000000-0000-4000-8000-000000000003",
  numbering: "13000000-0000-4000-8000-000000000001",
  storageGenerated: "18000000-0000-4000-8000-000000000001",
  storageSignedOne: "18000000-0000-4000-8000-000000000002",
  storageSignedTwo: "18000000-0000-4000-8000-000000000003",
  template: "12000000-0000-4000-8000-000000000001",
});

export function testSourceBundle(
  sourceHtml = '<!doctype html><html><body>{{ customer.name | default: "—" }}</body></html>',
): DocumentTemplateSourceBundle {
  const sourceCss = "body { color: #111; }";
  const assets = Object.freeze([]);
  return Object.freeze({
    sourceHtml,
    sourceCss,
    assets,
    checksum: computeTemplateSourceBundleChecksum({
      sourceHtml,
      sourceCss,
      assets,
    }),
  });
}

export interface M4ConfigurationFixture {
  readonly approvals: readonly DocumentApprovalRecord[];
  readonly documentType: DocumentTypeVersion;
  readonly template: DocumentTemplateVersion;
  readonly numbering: VersionedNumberingDefinition;
}

export function makeM4ConfigurationFixture(
  input: {
    readonly documentStatus?: DocumentConfigurationStatus;
    readonly numberingStatus?: NumberingVersionStatus;
    readonly productionEnabled?: boolean;
    readonly productionApproved?: boolean;
    readonly templateStatus?: DocumentConfigurationStatus;
  } = {},
): M4ConfigurationFixture {
  const numberingPayload: NumberingDefinitionPayload = {
    id: M4_TEST_IDS.numbering,
    key: "documents.retail_sale",
    version: "1.0.0",
    labels: Object.freeze({ en: "Retail sale", fr: "Vente au détail" }),
    scopeDimensions: Object.freeze(["workspace", "document_type"]),
    prefix: "INV-",
    suffix: "",
    numericWidth: 6,
    startingValue: "1",
    increment: "1",
    reset: "never",
    timezone: "America/Toronto",
    formatPattern: "{{prefix}}{{scope}}-{{sequence:6}}",
    deterministicSuffix: "none",
    importsAllowed: true,
    reservationsAllowed: false,
    reusePolicy: "never",
    allocationEvent: "official_document_created",
    requiredApprovalTypes: Object.freeze(["operational.numbering"]),
  };
  const numbering: VersionedNumberingDefinition = Object.freeze({
    ...numberingPayload,
    checksum: computeNumberingDefinitionChecksum(numberingPayload),
    status: input.numberingStatus ?? "approved",
  });

  const fieldSchema = Object.freeze({
    type: "object",
    additionalProperties: false,
    required: Object.freeze(["customer"]),
    properties: Object.freeze({ customer: Object.freeze({ type: "object" }) }),
  });
  const fieldSchemaChecksum = checksumJson(fieldSchema);
  const sourceBundle = testSourceBundle();
  const documentTypeIdentity = Object.freeze({
    id: M4_TEST_IDS.documentType,
    key: "retail.sale",
    version: "1.0.0",
  });
  const templatePayload: DocumentTemplateVersionPayload = {
    id: M4_TEST_IDS.template,
    key: "retail.sale.en_ca",
    documentTypeRef: documentTypeIdentity,
    version: "1.0.0",
    locale: "en-CA",
    rendererVersion: "playwright-pdf-v1",
    fieldSchema,
    fieldSchemaChecksum,
    sourceBundle,
    productionApproved: input.productionApproved ?? true,
    requiredApprovalTypes: Object.freeze(["legal.template"]),
  };
  const template: DocumentTemplateVersion = Object.freeze({
    ...templatePayload,
    checksum: computeDocumentTemplateVersionChecksum(templatePayload),
    status: input.templateStatus ?? "approved",
  });
  const templateReference: ImmutableVersionReference = Object.freeze({
    id: template.id,
    key: template.key,
    version: template.version,
    checksum: template.checksum,
  });
  const numberingReference: ImmutableVersionReference = Object.freeze({
    id: numbering.id,
    key: numbering.key,
    version: numbering.version,
    checksum: numbering.checksum,
  });
  const documentTypePayload: DocumentTypeVersionPayload = {
    ...documentTypeIdentity,
    labels: Object.freeze({ en: "Retail sale", fr: "Vente au détail" }),
    fieldSchema,
    fieldSchemaChecksum,
    templateVersionRefs: Object.freeze([templateReference]),
    numberingVersionRef: numberingReference,
    workflowVersionRef: null,
    taxPackVersionRef: null,
    calculationVersionRef: null,
    productionEnabled: input.productionEnabled ?? true,
    requiredApprovalTypes: Object.freeze(["legal.document_type"]),
  };
  const documentType: DocumentTypeVersion = Object.freeze({
    ...documentTypePayload,
    checksum: computeDocumentTypeVersionChecksum(documentTypePayload),
    status: input.documentStatus ?? "approved",
  });
  const approvals: readonly DocumentApprovalRecord[] = Object.freeze([
    approval(
      M4_TEST_IDS.approvalDocument,
      "document_type",
      documentType,
      "legal.document_type",
    ),
    approval(
      M4_TEST_IDS.approvalTemplate,
      "document_template",
      template,
      "legal.template",
    ),
    approval(
      M4_TEST_IDS.approvalNumbering,
      "numbering_definition",
      numbering,
      "operational.numbering",
    ),
  ]);
  return Object.freeze({ approvals, documentType, template, numbering });
}

function approval(
  id: string,
  artifactType: DocumentApprovalRecord["artifactType"],
  artifact: ImmutableVersionReference,
  approvalType: string,
): DocumentApprovalRecord {
  return Object.freeze({
    id,
    artifactType,
    artifactId: artifact.id,
    artifactKey: artifact.key,
    artifactVersion: artifact.version,
    artifactChecksum: artifact.checksum,
    approvalType,
    decision: "approved",
    decidedAt: "2026-07-01T12:00:00.000Z",
    expiresAt: "2027-07-01T12:00:00.000Z",
  });
}

export function renderInput(customerName: string): Readonly<{
  snapshot: Readonly<{ customer: Readonly<{ name: string }> }>;
  checksum: string;
}> {
  const snapshot = Object.freeze({
    customer: Object.freeze({ name: customerName }),
  });
  return Object.freeze({ snapshot, checksum: checksumJson(snapshot) });
}

export const PDF_CHECKSUM = sha256Hex("%PDF-1.7\nsynthetic fixture\n%%EOF");
