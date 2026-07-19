"use client";

import {
  AlertTriangle,
  ArrowRight,
  Check,
  ChevronRight,
  Download,
  FileCheck2,
  FileClock,
  FilePlus2,
  Files,
  History,
  LoaderCircle,
  RefreshCcw,
  ShieldAlert,
  ShieldCheck,
  Split,
  XOctagon,
} from "lucide-react";
import {
  type FormEvent,
  type ReactNode,
  useCallback,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
} from "react";
import { Button, Checkbox, Input, NativeSelect, Textarea } from "@vynlo/ui-web";

import type { Locale } from "../i18n/messages";
import { m4Messages, type M4Messages } from "../i18n/m4-messages";
import { legalOriginalMessages } from "../i18n/legal-original-messages";
import {
  localizedM4Label,
  m4DocumentActionEligibility,
  newM4IdempotencyKey,
  parseM4JsonObject,
  requestM4Json,
  type M4DocumentDetail,
  type M4DocumentListRow,
  type M4DocumentRequestResult,
  type M4DocumentType,
  type M4DocumentValidation,
  type M4DownloadGrant,
} from "../lib/m4-api-client";
import { LegalOriginalUpload } from "./legal-original-upload";
import {
  M4InlineStatus,
  M4OperatorRuntime,
  M4StatusPill,
  m4DangerButtonClass,
  m4FieldClass,
  m4LabelClass,
  m4PrimaryButtonClass,
  m4SecondaryButtonClass,
  m4SectionClass,
  m4TextAreaClass,
  type M4OperatorRuntimeState,
} from "./m4-operator-runtime";

export type M4DocumentView = "list" | "detail";

const previewTypeId = "40000000-0000-4000-8000-000000000401";
const previewTemplateVersionId = "40000000-0000-4000-8000-000000000402";
const previewDocumentId = "40000000-0000-4000-8000-000000000403";
const previewDealId = "40000000-0000-4000-8000-000000000404";
const checksum = "a".repeat(64);

const previewTypes: readonly M4DocumentType[] = [
  {
    activation_status: "active",
    field_schema: {
      additionalProperties: false,
      properties: {
        currency_code: { pattern: "^[A-Z]{3}$", type: "string" },
        customer_party_id: { format: "uuid", type: "string" },
        document_date: { format: "date", type: "string" },
        lines: { minItems: 1, type: "array" },
        location_id: { format: "uuid", type: "string" },
        notes: { maxLength: 10_000, type: "string" },
        seller_legal_entity_id: { format: "uuid", type: "string" },
      },
      required: [
        "document_date",
        "location_id",
        "seller_legal_entity_id",
        "customer_party_id",
        "currency_code",
        "lines",
      ],
      type: "object",
    },
    field_schema_checksum: checksum,
    id: previewTypeId,
    key: "generic_invoice",
    labels: { en: "Generic invoice", fr: "Facture générique" },
    official_generation_enabled: true,
    preview_generation_enabled: true,
    production_enabled: true,
    template_locales: ["en", "fr"],
    version: 2,
  },
  {
    activation_status: "test_passed",
    field_schema: { properties: {}, required: [], type: "object" },
    field_schema_checksum: "b".repeat(64),
    id: "40000000-0000-4000-8000-000000000405",
    key: "vehicle_purchase",
    labels: { en: "Vehicle purchase", fr: "Achat de véhicule" },
    official_generation_enabled: false,
    preview_generation_enabled: true,
    production_enabled: false,
    template_locales: ["en", "fr"],
    version: 1,
  },
];

const previewDocuments: readonly M4DocumentListRow[] = [
  {
    aggregate_version: 3,
    created_at: "2026-07-16T14:24:00.000Z",
    current_file_id: "40000000-0000-4000-8000-000000000406",
    deal_id: previewDealId,
    document_type_key: "generic_invoice",
    generated_at: "2026-07-16T14:24:06.000Z",
    id: previewDocumentId,
    job_status: "succeeded",
    locale: "en",
    mode: "official",
    official_number: "DOC-2026-00412",
    preview_artifact_id: null,
    status: "generated",
    superseded_by_document_id: null,
    supersedes_document_id: null,
  },
  {
    aggregate_version: 1,
    created_at: "2026-07-16T13:52:00.000Z",
    current_file_id: null,
    deal_id: "40000000-0000-4000-8000-000000000407",
    document_type_key: "vehicle_purchase",
    generated_at: null,
    id: "40000000-0000-4000-8000-000000000408",
    job_status: "queued",
    locale: "fr",
    mode: "preview",
    official_number: null,
    preview_artifact_id: null,
    status: "queued",
    superseded_by_document_id: null,
    supersedes_document_id: null,
  },
];

const previewDetail: M4DocumentDetail = {
  ...previewDocuments[0]!,
  calculation_snapshot: null,
  document_date: "2026-07-16",
  files: [
    {
      byte_size: 148_220,
      checksum_sha256: "c".repeat(64),
      created_at: "2026-07-16T14:24:06.000Z",
      current: true,
      filename: "DOC-2026-00412.pdf",
      id: "40000000-0000-4000-8000-000000000406",
      mime_type: "application/pdf",
      role: "generated_original",
      version: 1,
    },
  ],
  intended_signature_date: "2026-07-17",
  jobs: [
    {
      attempt_count: 1,
      failure_code: null,
      job_id: "40000000-0000-4000-8000-000000000409",
      review_required: false,
      status: "succeeded",
      updated_at: "2026-07-16T14:24:06.000Z",
    },
  ],
  render_input_checksum: "d".repeat(64),
  signed_at: null,
  tax_snapshot: null,
  version_snapshot: {
    documentTypeVersion: 2,
    rendererVersion: "1.0.0",
    templateVersionId: previewTemplateVersionId,
  },
  version_snapshot_checksum: "e".repeat(64),
  void_reason: null,
};

interface SchemaProperty {
  readonly enum?: readonly unknown[];
  readonly format?: string;
  readonly maxLength?: number;
  readonly type?: string | readonly string[];
}

type SchemaFieldValue = boolean | string;

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function formatDate(value: string | null, locale: Locale): string {
  if (!value) return "—";
  const date = new Date(value.includes("T") ? value : `${value}T00:00:00Z`);
  const options: Intl.DateTimeFormatOptions = {
    dateStyle: "medium",
    ...(value.includes("T") ? { timeStyle: "short" } : {}),
    timeZone: "UTC",
  };
  return Number.isNaN(date.valueOf())
    ? "—"
    : new Intl.DateTimeFormat(locale, options).format(date);
}

function formatBytes(value: number, locale: Locale): string {
  return new Intl.NumberFormat(locale, {
    maximumFractionDigits: 1,
    style: "unit",
    unit: value >= 1_000_000 ? "megabyte" : "kilobyte",
    unitDisplay: "short",
  }).format(value / (value >= 1_000_000 ? 1_000_000 : 1_000));
}

function shortId(value: string | null): string {
  return value ? value.slice(0, 8) : "—";
}

function safeError(copy: M4Messages, error: unknown): string {
  const correlation =
    typeof error === "object" &&
    error !== null &&
    "correlationId" in error &&
    typeof error.correlationId === "string"
      ? ` · ${error.correlationId}`
      : "";
  return `${copy.common.errorDescription}${correlation}`;
}

function schemaProperties(type: M4DocumentType | undefined): readonly Readonly<{
  key: string;
  property: SchemaProperty;
  required: boolean;
}>[] {
  const schema = type?.field_schema;
  const properties =
    schema &&
    typeof schema.properties === "object" &&
    schema.properties !== null &&
    !Array.isArray(schema.properties)
      ? (schema.properties as Readonly<Record<string, unknown>>)
      : {};
  const required = new Set(
    Array.isArray(schema?.required)
      ? schema.required.filter(
          (value): value is string => typeof value === "string",
        )
      : [],
  );
  return Object.entries(properties).flatMap(([key, value]) =>
    typeof value === "object" && value !== null && !Array.isArray(value)
      ? [
          {
            key,
            property: value as SchemaProperty,
            required: required.has(key),
          },
        ]
      : [],
  );
}

function propertyKinds(property: SchemaProperty): readonly string[] {
  return Array.isArray(property.type)
    ? property.type.filter((item): item is string => typeof item === "string")
    : typeof property.type === "string"
      ? [property.type]
      : ["string"];
}

function initialSchemaValues(
  fields: readonly Readonly<{ key: string; property: SchemaProperty }>[],
): Readonly<Record<string, SchemaFieldValue>> {
  return Object.fromEntries(
    fields.map(({ key, property }) => {
      const kinds = propertyKinds(property);
      if (kinds.includes("boolean")) return [key, false];
      if (key === "document_date") return [key, today()];
      if (key === "currency_code") return [key, "CAD"];
      if (kinds.includes("array")) return [key, "[]"];
      if (kinds.includes("object")) return [key, "{}"];
      return [key, ""];
    }),
  );
}

function serializeSchemaValues(
  fields: readonly Readonly<{
    key: string;
    property: SchemaProperty;
    required: boolean;
  }>[],
  values: Readonly<Record<string, SchemaFieldValue>>,
): Readonly<Record<string, unknown>> {
  const output: Record<string, unknown> = {};
  for (const { key, property, required } of fields) {
    const value = values[key];
    const kinds = propertyKinds(property);
    if (typeof value === "boolean") {
      output[key] = value;
      continue;
    }
    const normalized = value?.trim() ?? "";
    if (!normalized && !required && kinds.includes("null")) {
      output[key] = null;
      continue;
    }
    if (!normalized && !required) continue;
    if (kinds.includes("array") || kinds.includes("object")) {
      const parsed: unknown = JSON.parse(normalized);
      if (kinds.includes("array") && !Array.isArray(parsed)) {
        throw new TypeError(`structured_field_invalid:${key}`);
      }
      if (
        kinds.includes("object") &&
        (typeof parsed !== "object" || parsed === null || Array.isArray(parsed))
      ) {
        throw new TypeError(`structured_field_invalid:${key}`);
      }
      output[key] = parsed;
    } else if (kinds.includes("integer") || kinds.includes("number")) {
      const parsed = Number(normalized);
      if (
        !Number.isFinite(parsed) ||
        (!Number.isSafeInteger(parsed) && kinds.includes("integer"))
      ) {
        throw new TypeError(`number_field_invalid:${key}`);
      }
      output[key] = parsed;
    } else {
      output[key] = normalized;
    }
  }
  return Object.freeze(output);
}

function JsonSnapshot({ value }: { readonly value: unknown }) {
  return (
    <pre className="m-0 max-h-72 overflow-auto bg-[var(--ink)] p-4 text-xs leading-5 whitespace-pre-wrap text-[var(--paper)]">
      {JSON.stringify(value, null, 2)}
    </pre>
  );
}

function SchemaFieldInputs({
  copy,
  disabled,
  fields,
  onChange,
  values,
}: {
  readonly copy: M4Messages;
  readonly disabled: boolean;
  readonly fields: ReturnType<typeof schemaProperties>;
  readonly onChange: (key: string, value: SchemaFieldValue) => void;
  readonly values: Readonly<Record<string, SchemaFieldValue>>;
}) {
  if (fields.length === 0) {
    return (
      <p className="m-0 text-sm text-muted-foreground">
        {copy.documents.typeUnavailable}
      </p>
    );
  }
  return (
    <div className="grid gap-4 sm:grid-cols-2">
      {fields.map(({ key, property, required }) => {
        const kinds = propertyKinds(property);
        const label = copy.fieldLabels[key] ?? key;
        const value = values[key] ?? (kinds.includes("boolean") ? false : "");
        if (kinds.includes("boolean")) {
          return (
            <label
              className="flex min-h-12 items-center gap-3 border-b border-[var(--line)] text-sm font-semibold sm:col-span-2"
              key={key}
            >
              <Checkbox
                checked={value === true}
                disabled={disabled}
                onCheckedChange={(checked) => onChange(key, checked === true)}
              />
              {label}
            </label>
          );
        }
        if (kinds.includes("array") || kinds.includes("object")) {
          return (
            <label className={`${m4LabelClass} sm:col-span-2`} key={key}>
              {label}
              <Textarea
                className={m4TextAreaClass}
                disabled={disabled}
                onChange={(event) => onChange(key, event.target.value)}
                required={required}
                rows={5}
                spellCheck={false}
                value={String(value)}
              />
            </label>
          );
        }
        if (
          property.enum &&
          property.enum.every((item) => typeof item === "string")
        ) {
          return (
            <label className={m4LabelClass} key={key}>
              {label}
              <NativeSelect
                className={m4FieldClass}
                disabled={disabled}
                onChange={(event) => onChange(key, event.target.value)}
                required={required}
                value={String(value)}
              >
                <option value="">—</option>
                {property.enum.map((option) => (
                  <option key={String(option)} value={String(option)}>
                    {String(option)}
                  </option>
                ))}
              </NativeSelect>
            </label>
          );
        }
        return (
          <label className={m4LabelClass} key={key}>
            {label}
            <Input
              className={m4FieldClass}
              disabled={disabled}
              maxLength={property.maxLength}
              onChange={(event) => onChange(key, event.target.value)}
              required={required}
              type={
                property.format === "date"
                  ? "date"
                  : kinds.includes("number") || kinds.includes("integer")
                    ? "number"
                    : "text"
              }
              value={String(value)}
            />
          </label>
        );
      })}
    </div>
  );
}

function AvailabilityList({
  copy,
  locale,
  selectedId,
  types,
}: {
  readonly copy: M4Messages;
  readonly locale: Locale;
  readonly selectedId: string;
  readonly types: readonly M4DocumentType[];
}) {
  return (
    <div className="border-t border-[var(--ink)]">
      {types.map((type) => (
        <article
          className={`grid gap-3 border-b border-[var(--line)] py-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center ${
            type.id === selectedId
              ? "bg-[color-mix(in_srgb,var(--signal)_15%,transparent)]"
              : ""
          }`}
          key={type.id}
        >
          <div className="min-w-0">
            <h3 className="m-0 text-base">
              {localizedM4Label(
                type.labels,
                locale,
                copy.documents.typeUnavailable,
              )}
            </h3>
            <p className="mt-1 mb-0 font-mono text-xs text-muted-foreground">
              {type.key} · v{type.version} ·{" "}
              {type.field_schema_checksum.slice(0, 12)}
            </p>
          </div>
          <div className="flex flex-wrap gap-2 sm:justify-end">
            <M4StatusPill
              label={
                type.preview_generation_enabled
                  ? copy.documents.previewReady
                  : copy.documents.notProductionReady
              }
              status={type.preview_generation_enabled ? "approved" : "draft"}
            />
            <M4StatusPill
              label={
                type.official_generation_enabled
                  ? copy.documents.modes.official
                  : copy.documents.notProductionReady
              }
              status={type.official_generation_enabled ? "active" : "draft"}
            />
          </div>
        </article>
      ))}
    </div>
  );
}

function ValidationPanel({
  copy,
  result,
}: {
  readonly copy: M4Messages;
  readonly result: M4DocumentValidation | null;
}) {
  const gates = result
    ? ([
        [copy.documents.previewReady, result.preview_ready],
        [copy.documents.templateReady, result.template_ready],
        [copy.documents.calculationReady, result.calculation_ready],
        [copy.documents.taxReady, result.tax_ready],
        [copy.documents.officialNumber, result.numbering_ready],
      ] as const)
    : [];
  return (
    <section aria-labelledby="m4-validation-heading" className={m4SectionClass}>
      <div className="grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)]">
        <header>
          <p className="mb-2 font-mono text-xs font-bold text-[var(--rust)] uppercase">
            02
          </p>
          <h2 className="m-0 text-2xl" id="m4-validation-heading">
            {copy.documents.validation}
          </h2>
        </header>
        {!result ? (
          <p className="m-0 border-l border-border pl-4 text-sm text-muted-foreground">
            {copy.documents.validationRequired}
          </p>
        ) : (
          <div className="grid gap-5">
            <ul className="m-0 grid list-none gap-0 border-t border-[var(--ink)] p-0 sm:grid-cols-2">
              {gates.map(([label, passed]) => (
                <li
                  className="flex min-h-12 items-center gap-3 border-b border-[var(--line)] py-2 text-sm font-semibold sm:px-3"
                  key={label}
                >
                  {passed ? (
                    <Check
                      aria-hidden="true"
                      className="text-[var(--ink)]"
                      size={18}
                    />
                  ) : (
                    <XOctagon
                      aria-hidden="true"
                      className="text-[var(--rust)]"
                      size={18}
                    />
                  )}
                  {label}
                </li>
              ))}
            </ul>
            {result.errors.length > 0 ? (
              <div className="rounded-[var(--radius-panel)] border border-destructive/40 bg-destructive/5 p-4">
                <h3 className="mt-0 mb-2 text-sm">
                  {copy.documents.validationErrors}
                </h3>
                <ul className="m-0 pl-5 text-sm">
                  {result.errors.map((error) => (
                    <li key={error}>{error}</li>
                  ))}
                </ul>
              </div>
            ) : (
              <p className="m-0 flex items-center gap-3 rounded-[var(--radius-control)] border border-primary/30 bg-primary/5 p-3 text-sm font-semibold">
                <ShieldCheck aria-hidden="true" size={20} />
                {copy.documents.validationPassed}
              </p>
            )}
            {result.warnings.length > 0 ? (
              <div>
                <h3 className="text-sm">{copy.documents.validationWarnings}</h3>
                <ul className="pl-5 text-sm text-muted-foreground">
                  {result.warnings.map((warning) => (
                    <li key={warning}>{warning}</li>
                  ))}
                </ul>
              </div>
            ) : null}
          </div>
        )}
      </div>
    </section>
  );
}

function DocumentQueue({
  copy,
  documents,
  locale,
  loading,
  onRefresh,
  previewMode,
}: {
  readonly copy: M4Messages;
  readonly documents: readonly M4DocumentListRow[];
  readonly locale: Locale;
  readonly loading: boolean;
  readonly onRefresh: () => void;
  readonly previewMode: boolean;
}) {
  return (
    <section
      aria-labelledby="m4-document-queue-heading"
      className={m4SectionClass}
    >
      <div className="mb-5 flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="mb-2 font-mono text-xs font-bold text-[var(--rust)] uppercase">
            Queue
          </p>
          <h2 className="m-0 text-2xl" id="m4-document-queue-heading">
            {copy.documents.queue}
          </h2>
        </div>
        <Button
          className={m4SecondaryButtonClass}
          disabled={loading}
          onClick={onRefresh}
          type="button"
        >
          <RefreshCcw
            aria-hidden="true"
            className={loading ? "animate-spin motion-reduce:animate-none" : ""}
            size={17}
          />
          {copy.documents.refresh}
        </Button>
      </div>
      {documents.length === 0 ? (
        <div className="border-y border-[var(--line)] py-12">
          <h3 className="m-0 text-xl">{copy.documents.emptyHeading}</h3>
          <p className="mt-2 mb-0 text-sm text-muted-foreground">
            {copy.documents.emptyDescription}
          </p>
        </div>
      ) : (
        <div className="border-t border-[var(--ink)]">
          {documents.map((document) => (
            <article
              className="group grid gap-4 border-b border-[var(--line)] py-5 sm:grid-cols-[minmax(0,1.2fr)_minmax(10rem,0.7fr)_auto] sm:items-center"
              key={document.id}
            >
              <div className="min-w-0">
                <p className="m-0 font-mono text-[0.68rem] font-bold tracking-[0.08em] text-muted-foreground uppercase">
                  {copy.documents.modes[document.mode] ?? document.mode} ·{" "}
                  {shortId(document.id)}
                </p>
                <h3 className="my-1 text-lg tracking-[-0.02em]">
                  {document.official_number ?? document.document_type_key}
                </h3>
                <p className="m-0 text-xs text-muted-foreground">
                  {formatDate(document.created_at, locale)} ·{" "}
                  {shortId(document.deal_id)}
                </p>
              </div>
              <div className="flex flex-wrap gap-2">
                <M4StatusPill
                  label={
                    copy.documents.statuses[document.status] ?? document.status
                  }
                  status={document.status}
                />
                {document.job_status ? (
                  <M4StatusPill
                    label={
                      copy.documents.jobStatuses[document.job_status] ??
                      document.job_status
                    }
                    status={document.job_status}
                  />
                ) : null}
              </div>
              <a
                className="inline-flex min-h-11 items-center justify-center gap-2 border border-[var(--line)] px-3 text-sm font-bold text-[var(--ink)] no-underline hover:border-[var(--ink)] hover:bg-[var(--surface)]"
                href={`/documents/${document.id}${previewMode ? "?preview=m4" : ""}`}
              >
                {copy.documents.openDocument}
                <ChevronRight aria-hidden="true" size={16} />
              </a>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}

function DocumentListSurface({
  copy,
  locale,
  runtime,
}: {
  readonly copy: M4Messages;
  readonly locale: Locale;
  readonly runtime: M4OperatorRuntimeState;
}) {
  const [types, setTypes] = useState<readonly M4DocumentType[]>([]);
  const [documents, setDocuments] = useState<readonly M4DocumentListRow[]>([]);
  const [selectedTypeId, setSelectedTypeId] = useState("");
  const [dealId, setDealId] = useState(
    runtime.previewMode ? previewDealId : "",
  );
  const [templateVersionId, setTemplateVersionId] = useState(
    runtime.previewMode ? previewTemplateVersionId : "",
  );
  const [documentDate, setDocumentDate] = useState(today());
  const [signatureDate, setSignatureDate] = useState("");
  const [calculationEvidence, setCalculationEvidence] = useState("");
  const [taxEvidence, setTaxEvidence] = useState("");
  const [documentLocale, setDocumentLocale] = useState<Locale>(locale);
  const [fieldValues, setFieldValues] = useState<
    Readonly<Record<string, SchemaFieldValue>>
  >({});
  const [validation, setValidation] = useState<M4DocumentValidation | null>(
    null,
  );
  const [reason, setReason] = useState("");
  const [allocationConfirmed, setAllocationConfirmed] = useState(false);
  const [receipt, setReceipt] = useState<M4DocumentRequestResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState<
    "official" | "preview" | "validate" | null
  >(null);
  const [error, setError] = useState<string | null>(null);
  const officialKey = useRef<string | null>(null);

  const selectedType = types.find((type) => type.id === selectedTypeId);
  const fields = useMemo(() => schemaProperties(selectedType), [selectedType]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [nextTypes, nextDocuments] = runtime.previewMode
        ? ([previewTypes, previewDocuments] as const)
        : await Promise.all([
            requestM4Json<readonly M4DocumentType[]>({
              context: runtime.apiContext,
              path: "/api/v1/document-types",
            }),
            requestM4Json<readonly M4DocumentListRow[]>({
              context: runtime.apiContext,
              path: "/api/v1/documents?limit=50",
            }),
          ]);
      setTypes(nextTypes);
      setDocuments(nextDocuments);
      setSelectedTypeId((current) =>
        nextTypes.some((type) => type.id === current)
          ? current
          : (nextTypes[0]?.id ?? ""),
      );
    } catch (loadError) {
      setError(safeError(copy, loadError));
    } finally {
      setLoading(false);
    }
  }, [copy, runtime.apiContext, runtime.previewMode]);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      setFieldValues(initialSchemaValues(fields));
      setValidation(null);
      setReceipt(null);
      setAllocationConfirmed(false);
      officialKey.current = null;
    }, 0);
    return () => window.clearTimeout(timer);
  }, [fields]);

  function invalidate(): void {
    setValidation(null);
    setReceipt(null);
    setAllocationConfirmed(false);
    officialKey.current = null;
  }

  function requestBody() {
    if (!selectedType) throw new TypeError("document_type_required");
    return {
      calculationEvidence: calculationEvidence.trim()
        ? parseM4JsonObject(calculationEvidence)
        : null,
      dealId,
      documentDate,
      documentFields: serializeSchemaValues(fields, fieldValues),
      documentTypeId: selectedType.id,
      intendedSignatureDate: signatureDate || null,
      locale: documentLocale,
      taxEvidence: taxEvidence.trim() ? parseM4JsonObject(taxEvidence) : null,
      templateVersionId,
    } as const;
  }

  async function validate(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    setWorking("validate");
    setError(null);
    setReceipt(null);
    try {
      const next = runtime.previewMode
        ? ({
            calculation_ready: true,
            document_type_ready: true,
            errors: [],
            numbering_ready: selectedType?.official_generation_enabled === true,
            official_ready: selectedType?.official_generation_enabled === true,
            preview_ready: selectedType?.preview_generation_enabled === true,
            tax_ready: true,
            template_ready: Boolean(templateVersionId),
            warnings: [],
          } satisfies M4DocumentValidation)
        : await requestM4Json<M4DocumentValidation>({
            body: requestBody(),
            context: runtime.apiContext,
            idempotencyKey: newM4IdempotencyKey("document-validate"),
            method: "POST",
            path: "/api/v1/documents/validate",
          });
      setValidation(next);
    } catch (validationError) {
      setError(
        validationError instanceof SyntaxError ||
          validationError instanceof TypeError
          ? copy.documents.fieldInvalidJson
          : safeError(copy, validationError),
      );
    } finally {
      setWorking(null);
    }
  }

  async function generate(mode: "official" | "preview"): Promise<void> {
    setWorking(mode);
    setError(null);
    try {
      const body = requestBody();
      const next = runtime.previewMode
        ? ({
            aggregate_version: 1,
            audit_event_id: "40000000-0000-4000-8000-000000000410",
            document_id:
              mode === "official"
                ? "40000000-0000-4000-8000-000000000411"
                : "40000000-0000-4000-8000-000000000412",
            document_status: "queued",
            job_id: "40000000-0000-4000-8000-000000000413",
            number_allocation_id:
              mode === "official"
                ? "40000000-0000-4000-8000-000000000414"
                : null,
            official_number: mode === "official" ? "DOC-2026-00413" : null,
            outbox_event_id: "40000000-0000-4000-8000-000000000415",
            replayed: false,
          } satisfies M4DocumentRequestResult)
        : await requestM4Json<M4DocumentRequestResult>({
            body: mode === "official" ? { ...body, reason } : body,
            context: runtime.apiContext,
            idempotencyKey:
              mode === "official"
                ? (officialKey.current ??=
                    newM4IdempotencyKey("official-document"))
                : newM4IdempotencyKey("document-preview"),
            method: "POST",
            path:
              mode === "official"
                ? "/api/v1/documents/official"
                : "/api/v1/documents/preview",
          });
      setReceipt(next);
      setDocuments((current) => [
        {
          aggregate_version: next.aggregate_version,
          created_at: new Date().toISOString(),
          current_file_id: null,
          deal_id: dealId,
          document_type_key: selectedType?.key ?? "document",
          generated_at: null,
          id: next.document_id,
          job_status: "queued",
          locale: documentLocale,
          mode,
          official_number: next.official_number,
          preview_artifact_id: null,
          status: next.document_status,
          superseded_by_document_id: null,
          supersedes_document_id: null,
        },
        ...current.filter((document) => document.id !== next.document_id),
      ]);
    } catch (generationError) {
      setError(
        generationError instanceof SyntaxError ||
          generationError instanceof TypeError
          ? copy.documents.fieldInvalidJson
          : safeError(copy, generationError),
      );
    } finally {
      setWorking(null);
    }
  }

  return (
    <div className="mx-auto max-w-[90rem] px-4 sm:px-6 lg:px-8">
      {error ? (
        <div
          className="mt-5 flex items-start gap-3 rounded-[var(--radius-panel)] border border-destructive/40 bg-destructive/5 p-4"
          role="alert"
        >
          <AlertTriangle
            aria-hidden="true"
            className="mt-0.5 shrink-0"
            size={19}
          />
          <p className="m-0 text-sm font-semibold">{error}</p>
        </div>
      ) : null}

      <section
        aria-labelledby="m4-availability-heading"
        className={m4SectionClass}
      >
        <div className="grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)]">
          <header>
            <p className="mb-2 font-mono text-xs font-bold text-[var(--rust)] uppercase">
              01
            </p>
            <h2 className="m-0 text-2xl" id="m4-availability-heading">
              {copy.documents.available}
            </h2>
            <p className="mt-3 mb-0 text-sm leading-6 text-muted-foreground">
              {copy.documents.availabilityHint}
            </p>
          </header>
          {loading ? (
            <p
              className="m-0 flex items-center gap-3 text-sm font-semibold"
              role="status"
            >
              <LoaderCircle
                aria-hidden="true"
                className="animate-spin motion-reduce:animate-none"
                size={18}
              />
              {copy.common.loading}
            </p>
          ) : (
            <AvailabilityList
              copy={copy}
              locale={locale}
              selectedId={selectedTypeId}
              types={types}
            />
          )}
        </div>
      </section>

      <form onSubmit={(event) => void validate(event)}>
        <section
          aria-labelledby="m4-generation-heading"
          className={m4SectionClass}
        >
          <div className="grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)]">
            <header>
              <p className="mb-2 font-mono text-xs font-bold text-[var(--rust)] uppercase">
                Fields
              </p>
              <h2 className="m-0 text-2xl" id="m4-generation-heading">
                {copy.documents.generation}
              </h2>
              <p className="mt-3 mb-0 text-sm leading-6 text-muted-foreground">
                {copy.documents.documentFieldsHint}
              </p>
            </header>
            <div className="grid gap-5">
              <div className="grid gap-4 sm:grid-cols-2">
                <label className={m4LabelClass}>
                  {copy.documents.documentType}
                  <NativeSelect
                    className={m4FieldClass}
                    disabled={working !== null || types.length === 0}
                    onChange={(event) => {
                      setSelectedTypeId(event.target.value);
                      invalidate();
                    }}
                    required
                    value={selectedTypeId}
                  >
                    {types.map((type) => (
                      <option key={type.id} value={type.id}>
                        {localizedM4Label(
                          type.labels,
                          locale,
                          copy.documents.typeUnavailable,
                        )}
                      </option>
                    ))}
                  </NativeSelect>
                </label>
                <label className={m4LabelClass}>
                  {copy.documents.locale}
                  <NativeSelect
                    className={m4FieldClass}
                    disabled={working !== null}
                    onChange={(event) => {
                      setDocumentLocale(event.target.value as Locale);
                      invalidate();
                    }}
                    value={documentLocale}
                  >
                    <option value="en">{copy.common.localeNames.en}</option>
                    <option value="fr">{copy.common.localeNames.fr}</option>
                  </NativeSelect>
                </label>
                <label className={m4LabelClass}>
                  {copy.documents.dealId}
                  <Input
                    className={m4FieldClass}
                    disabled={working !== null}
                    onChange={(event) => {
                      setDealId(event.target.value);
                      invalidate();
                    }}
                    required
                    type="text"
                    value={dealId}
                  />
                </label>
                <label className={m4LabelClass}>
                  {copy.documents.templateVersionId}
                  <Input
                    className={m4FieldClass}
                    disabled={working !== null}
                    onChange={(event) => {
                      setTemplateVersionId(event.target.value);
                      invalidate();
                    }}
                    required
                    type="text"
                    value={templateVersionId}
                  />
                </label>
                <label className={m4LabelClass}>
                  {copy.documents.documentDate}
                  <Input
                    className={m4FieldClass}
                    disabled={working !== null}
                    onChange={(event) => {
                      setDocumentDate(event.target.value);
                      invalidate();
                    }}
                    required
                    type="date"
                    value={documentDate}
                  />
                </label>
                <label className={m4LabelClass}>
                  {copy.documents.intendedSignatureDate}
                  <Input
                    className={m4FieldClass}
                    disabled={working !== null}
                    onChange={(event) => {
                      setSignatureDate(event.target.value);
                      invalidate();
                    }}
                    type="date"
                    value={signatureDate}
                  />
                </label>
              </div>
              <fieldset className="m-0 grid gap-4 border-0 border-t border-[var(--line)] p-0 pt-5">
                <legend className="mb-4 text-sm font-bold">
                  {copy.documents.documentFields}
                </legend>
                <SchemaFieldInputs
                  copy={copy}
                  disabled={working !== null}
                  fields={fields}
                  onChange={(key, value) => {
                    setFieldValues((current) => ({ ...current, [key]: value }));
                    invalidate();
                  }}
                  values={fieldValues}
                />
              </fieldset>
              <details className="border-y border-[var(--line)] py-3">
                <summary className="min-h-11 cursor-pointer text-sm font-bold">
                  {copy.documents.calculationReady} · {copy.documents.taxReady}
                </summary>
                <div className="mt-4 grid gap-4 sm:grid-cols-2">
                  <p className="m-0 text-sm leading-6 text-muted-foreground sm:col-span-2">
                    {copy.documents.evidenceHint}
                  </p>
                  <label className={m4LabelClass}>
                    {copy.documents.calculationEvidence}
                    <Textarea
                      className={m4TextAreaClass}
                      disabled={working !== null}
                      onChange={(event) => {
                        setCalculationEvidence(event.target.value);
                        invalidate();
                      }}
                      rows={5}
                      value={calculationEvidence}
                    />
                  </label>
                  <label className={m4LabelClass}>
                    {copy.documents.taxEvidence}
                    <Textarea
                      className={m4TextAreaClass}
                      disabled={working !== null}
                      onChange={(event) => {
                        setTaxEvidence(event.target.value);
                        invalidate();
                      }}
                      rows={5}
                      value={taxEvidence}
                    />
                  </label>
                </div>
              </details>
              <Button
                className={`${m4SecondaryButtonClass} justify-self-start`}
                disabled={
                  !runtime.canWrite || working !== null || !selectedType
                }
                type="submit"
              >
                {working === "validate" ? (
                  <LoaderCircle
                    aria-hidden="true"
                    className="animate-spin motion-reduce:animate-none"
                    size={17}
                  />
                ) : (
                  <ShieldCheck aria-hidden="true" size={17} />
                )}
                {copy.documents.validateAction}
              </Button>
            </div>
          </div>
        </section>
      </form>

      <ValidationPanel copy={copy} result={validation} />

      <section aria-labelledby="m4-finalize-heading" className={m4SectionClass}>
        <div className="grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)]">
          <header>
            <p className="mb-2 font-mono text-xs font-bold text-[var(--rust)] uppercase">
              03
            </p>
            <h2 className="m-0 text-2xl" id="m4-finalize-heading">
              {copy.documents.previewAction}
            </h2>
            <p className="mt-3 mb-0 text-sm leading-6 text-muted-foreground">
              {copy.documents.previewHint}
            </p>
          </header>
          <div className="grid gap-6">
            <div className="grid gap-4 border-b border-[var(--line)] pb-6 sm:grid-cols-2">
              <div>
                <h3 className="mt-0 mb-2 text-lg">
                  {copy.documents.previewAction}
                </h3>
                <p className="mt-0 mb-4 text-sm text-muted-foreground">
                  {copy.documents.previewNumberPolicy}
                </p>
                <Button
                  className={m4SecondaryButtonClass}
                  disabled={
                    !runtime.canWrite ||
                    working !== null ||
                    validation?.preview_ready !== true
                  }
                  onClick={() => void generate("preview")}
                  type="button"
                >
                  {working === "preview" ? (
                    <LoaderCircle
                      aria-hidden="true"
                      className="animate-spin motion-reduce:animate-none"
                      size={17}
                    />
                  ) : (
                    <FileClock aria-hidden="true" size={17} />
                  )}
                  {copy.documents.previewAction}
                </Button>
              </div>
              <div className="grid gap-4 border-l-0 border-[var(--rust)] sm:border-l sm:pl-5">
                <div>
                  <h3 className="mt-0 mb-2 text-lg">
                    {copy.documents.officialAction}
                  </h3>
                  <p className="m-0 text-sm text-muted-foreground">
                    {copy.documents.confirmAllocationHint}
                  </p>
                </div>
                <label className={m4LabelClass}>
                  {copy.documents.actionReason}
                  <Textarea
                    className={m4TextAreaClass}
                    disabled={working !== null}
                    onChange={(event) => {
                      setReason(event.target.value);
                      officialKey.current = null;
                    }}
                    required
                    rows={3}
                    value={reason}
                  />
                  <span className="normal-case tracking-normal font-normal">
                    {copy.documents.actionReasonHint}
                  </span>
                </label>
                <label className="flex min-h-12 items-start gap-3 text-sm font-bold">
                  <Checkbox
                    checked={allocationConfirmed}
                    className="mt-1 size-5 shrink-0"
                    disabled={working !== null}
                    onCheckedChange={(checked) =>
                      setAllocationConfirmed(checked === true)
                    }
                  />
                  {copy.documents.confirmAllocation}
                </label>
                <Button
                  className={m4PrimaryButtonClass}
                  disabled={
                    !runtime.canWrite ||
                    working !== null ||
                    validation?.official_ready !== true ||
                    !allocationConfirmed ||
                    reason.trim().length === 0
                  }
                  onClick={() => void generate("official")}
                  type="button"
                >
                  {working === "official" ? (
                    <LoaderCircle
                      aria-hidden="true"
                      className="animate-spin motion-reduce:animate-none"
                      size={17}
                    />
                  ) : (
                    <FilePlus2 aria-hidden="true" size={17} />
                  )}
                  {copy.documents.officialAction}
                </Button>
                {validation?.official_ready !== true ? (
                  <p className="m-0 text-sm font-semibold text-[var(--rust)]">
                    {copy.documents.officialUnavailable}
                  </p>
                ) : null}
              </div>
            </div>
            {receipt ? (
              <div
                className="grid gap-4 rounded-[var(--radius-panel)] border border-border bg-card p-4"
                role="status"
              >
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <h3 className="m-0 text-lg">
                    {copy.documents.generationResult}
                  </h3>
                  <M4StatusPill
                    label={
                      copy.documents.statuses[receipt.document_status] ??
                      receipt.document_status
                    }
                    status={receipt.document_status}
                  />
                </div>
                <dl className="m-0 grid gap-3 text-sm sm:grid-cols-3">
                  <div>
                    <dt className="text-xs font-bold text-muted-foreground uppercase">
                      {copy.documents.officialNumber}
                    </dt>
                    <dd className="m-0 mt-1 font-mono font-bold">
                      {receipt.official_number ?? "—"}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-xs font-bold text-muted-foreground uppercase">
                      {copy.documents.jobId}
                    </dt>
                    <dd className="m-0 mt-1 font-mono">
                      {shortId(receipt.job_id)}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-xs font-bold text-muted-foreground uppercase">
                      ID
                    </dt>
                    <dd className="m-0 mt-1 font-mono">
                      {shortId(receipt.document_id)}
                    </dd>
                  </div>
                </dl>
                <p className="m-0 text-sm text-muted-foreground">
                  {copy.documents.generationQueued}
                </p>
                <a
                  className={`${m4SecondaryButtonClass} justify-self-start no-underline`}
                  href={`/documents/${receipt.document_id}${runtime.previewMode ? "?preview=m4" : ""}`}
                >
                  {copy.documents.openDocument}
                  <ArrowRight aria-hidden="true" size={16} />
                </a>
              </div>
            ) : null}
          </div>
        </div>
      </section>

      <DocumentQueue
        copy={copy}
        documents={documents}
        locale={locale}
        loading={loading}
        onRefresh={() => void load()}
        previewMode={runtime.previewMode}
      />
    </div>
  );
}

function ReasonCommand({
  action,
  children,
  copy,
  danger = false,
  disabled,
  heading,
  hint,
  icon,
  working,
}: {
  readonly action: (reason: string) => Promise<void>;
  readonly children?: ReactNode;
  readonly copy: M4Messages;
  readonly danger?: boolean;
  readonly disabled: boolean;
  readonly heading: string;
  readonly hint: string;
  readonly icon: ReactNode;
  readonly working: boolean;
}) {
  const [reason, setReason] = useState("");
  return (
    <form
      className="grid gap-4 border-t border-[var(--line)] py-5"
      onSubmit={(event) => {
        event.preventDefault();
        void action(reason.trim()).then(() => setReason(""));
      }}
    >
      <div>
        <h3 className="m-0 text-base">{heading}</h3>
        <p className="mt-2 mb-0 text-sm leading-6 text-muted-foreground">
          {hint}
        </p>
      </div>
      {children}
      <label className={m4LabelClass}>
        {copy.documents.actionReason}
        <Textarea
          className={m4TextAreaClass}
          disabled={disabled || working}
          onChange={(event) => setReason(event.target.value)}
          required
          rows={3}
          value={reason}
        />
      </label>
      <Button
        className={`${danger ? m4DangerButtonClass : m4SecondaryButtonClass} justify-self-start`}
        disabled={disabled || working || reason.trim().length === 0}
        type="submit"
      >
        {working ? (
          <LoaderCircle
            aria-hidden="true"
            className="animate-spin motion-reduce:animate-none"
            size={17}
          />
        ) : (
          icon
        )}
        {heading}
      </Button>
    </form>
  );
}

function DocumentDetailSurface({
  copy,
  documentId,
  locale,
  runtime,
}: {
  readonly copy: M4Messages;
  readonly documentId: string;
  readonly locale: Locale;
  readonly runtime: M4OperatorRuntimeState;
}) {
  const [document, setDocument] = useState<M4DocumentDetail | null>(null);
  const [types, setTypes] = useState<readonly M4DocumentType[]>([]);
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState("");
  const [supersedeTemplateId, setSupersedeTemplateId] = useState(
    runtime.previewMode ? previewTemplateVersionId : "",
  );
  const [supersedeDate, setSupersedeDate] = useState(today());
  const [supersedeSignatureDate, setSupersedeSignatureDate] = useState("");
  const [supersedeCalculationEvidence, setSupersedeCalculationEvidence] =
    useState("");
  const [supersedeTaxEvidence, setSupersedeTaxEvidence] = useState("");
  const [supersedeValues, setSupersedeValues] = useState<
    Readonly<Record<string, SchemaFieldValue>>
  >({});
  const headingId = useId();

  const type = types.find(
    (candidate) => candidate.key === document?.document_type_key,
  );
  const fields = useMemo(() => schemaProperties(type), [type]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [nextDocument, nextTypes] = runtime.previewMode
        ? ([{ ...previewDetail, id: documentId }, previewTypes] as const)
        : await Promise.all([
            requestM4Json<M4DocumentDetail>({
              context: runtime.apiContext,
              path: `/api/v1/documents/${encodeURIComponent(documentId)}`,
            }),
            requestM4Json<readonly M4DocumentType[]>({
              context: runtime.apiContext,
              path: "/api/v1/document-types",
            }),
          ]);
      setDocument(nextDocument);
      setTypes(nextTypes);
      setSupersedeDate(nextDocument.document_date ?? today());
    } catch (loadError) {
      setError(safeError(copy, loadError));
    } finally {
      setLoading(false);
    }
  }, [copy, documentId, runtime.apiContext, runtime.previewMode]);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  useEffect(() => {
    const timer = window.setTimeout(
      () => setSupersedeValues(initialSchemaValues(fields)),
      0,
    );
    return () => window.clearTimeout(timer);
  }, [fields]);

  async function mutate(
    action: "mark-signed" | "retry-render" | "void",
    reason: string,
  ): Promise<void> {
    if (!document) return;
    setWorking(action);
    setError(null);
    setNotice("");
    try {
      if (!runtime.previewMode) {
        await requestM4Json({
          body: { expectedVersion: document.aggregate_version, reason },
          context: runtime.apiContext,
          idempotencyKey: newM4IdempotencyKey(`document-${action}`),
          method: "POST",
          path: `/api/v1/documents/${encodeURIComponent(document.id)}/${action}`,
        });
      }
      setNotice(
        action === "retry-render"
          ? copy.documents.generationQueued
          : copy.common.saved,
      );
      await load();
    } catch (mutationError) {
      setError(safeError(copy, mutationError));
    } finally {
      setWorking(null);
    }
  }

  async function supersede(reason: string): Promise<void> {
    if (!document || !type) return;
    setWorking("supersede");
    setError(null);
    try {
      const body = {
        calculationEvidence: supersedeCalculationEvidence.trim()
          ? parseM4JsonObject(supersedeCalculationEvidence)
          : null,
        dealId: document.deal_id,
        documentDate: supersedeDate,
        documentFields: serializeSchemaValues(fields, supersedeValues),
        documentTypeId: type.id,
        expectedVersion: document.aggregate_version,
        intendedSignatureDate: supersedeSignatureDate || null,
        locale: document.locale,
        reason,
        taxEvidence: supersedeTaxEvidence.trim()
          ? parseM4JsonObject(supersedeTaxEvidence)
          : null,
        templateVersionId: supersedeTemplateId,
      };
      const result = runtime.previewMode
        ? ({ document_id: "40000000-0000-4000-8000-000000000416" } as const)
        : await requestM4Json<M4DocumentRequestResult>({
            body,
            context: runtime.apiContext,
            idempotencyKey: newM4IdempotencyKey("document-supersede"),
            method: "POST",
            path: `/api/v1/documents/${encodeURIComponent(document.id)}/supersede`,
          });
      setNotice(`${copy.documents.supersede}: ${shortId(result.document_id)}`);
      await load();
    } catch (supersedeError) {
      setError(
        supersedeError instanceof SyntaxError ||
          supersedeError instanceof TypeError
          ? copy.documents.fieldInvalidJson
          : safeError(copy, supersedeError),
      );
    } finally {
      setWorking(null);
    }
  }

  async function downloadFile(fileId: string): Promise<void> {
    if (!document) return;
    setWorking(`download:${fileId}`);
    setError(null);
    try {
      if (runtime.previewMode) {
        setNotice(copy.documents.previewHint);
      } else {
        const grant = await requestM4Json<M4DownloadGrant>({
          context: runtime.apiContext,
          path: `/api/v1/documents/${encodeURIComponent(document.id)}/files/${encodeURIComponent(fileId)}/download`,
        });
        window.location.assign(grant.download.url);
      }
    } catch (downloadError) {
      setError(safeError(copy, downloadError));
    } finally {
      setWorking(null);
    }
  }

  async function downloadPreviewArtifact(artifactId: string): Promise<void> {
    setWorking(`download-preview:${artifactId}`);
    setError(null);
    try {
      if (runtime.previewMode) {
        setNotice(copy.documents.previewHint);
      } else {
        const grant = await requestM4Json<M4DownloadGrant>({
          body: { expiresInSeconds: 60 },
          context: runtime.apiContext,
          idempotencyKey: newM4IdempotencyKey("document-preview-download"),
          method: "POST",
          path: `/api/v1/document-preview-artifacts/${encodeURIComponent(artifactId)}/download-grants`,
        });
        window.location.assign(grant.download.url);
      }
    } catch (downloadError) {
      setError(safeError(copy, downloadError));
    } finally {
      setWorking(null);
    }
  }

  if (loading) {
    return (
      <div
        className="flex min-h-64 items-center justify-center gap-3"
        role="status"
      >
        <LoaderCircle
          aria-hidden="true"
          className="animate-spin motion-reduce:animate-none"
          size={20}
        />
        {copy.common.loading}
      </div>
    );
  }
  if (!document) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-16">
        <M4InlineStatus error message={error ?? copy.common.errorDescription} />
      </div>
    );
  }

  const previewArtifactId = document.preview_artifact_id;
  const actionEligibility = m4DocumentActionEligibility(document);

  return (
    <div className="mx-auto max-w-[90rem] px-4 sm:px-6 lg:px-8">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--line)] py-5">
        <a
          className="inline-flex min-h-11 items-center gap-2 text-sm font-bold text-[var(--ink)]"
          href={`/documents${runtime.previewMode ? "?preview=m4" : ""}`}
        >
          {copy.common.back}
        </a>
        <Button
          className={m4SecondaryButtonClass}
          onClick={() => void load()}
          type="button"
        >
          <RefreshCcw aria-hidden="true" size={17} />
          {copy.documents.refresh}
        </Button>
      </div>

      {error ? <M4InlineStatus error message={error} /> : null}
      {notice ? <M4InlineStatus message={notice} /> : null}

      <section aria-labelledby={headingId} className={m4SectionClass}>
        <div className="grid gap-8 lg:grid-cols-[minmax(0,1.3fr)_minmax(18rem,0.7fr)]">
          <div>
            <p className="mb-2 font-mono text-xs font-bold text-[var(--rust)] uppercase">
              {copy.documents.modes[document.mode]} ·{" "}
              {document.document_type_key}
            </p>
            <h2
              className="m-0 text-[clamp(2.2rem,7vw,5.6rem)] leading-[0.9] tracking-[-0.06em]"
              id={headingId}
            >
              {document.official_number ?? copy.documents.previewAction}
            </h2>
            <p className="mt-4 mb-0 font-mono text-xs text-muted-foreground">
              {document.id}
            </p>
          </div>
          <dl className="m-0 border-t border-[var(--ink)] text-sm">
            {[
              [
                copy.documents.status,
                <M4StatusPill
                  key="status"
                  label={
                    copy.documents.statuses[document.status] ?? document.status
                  }
                  status={document.status}
                />,
              ],
              [copy.documents.created, formatDate(document.created_at, locale)],
              [copy.documents.signedAt, formatDate(document.signed_at, locale)],
              [copy.documents.version, String(document.aggregate_version)],
            ].map(([label, value]) => (
              <div
                className="grid grid-cols-[7rem_minmax(0,1fr)] gap-3 border-b border-[var(--line)] py-3"
                key={String(label)}
              >
                <dt className="font-bold text-muted-foreground">{label}</dt>
                <dd className="m-0 justify-self-end text-right">{value}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      <section aria-labelledby="m4-files-heading" className={m4SectionClass}>
        <div className="grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)]">
          <header>
            <Files aria-hidden="true" size={24} strokeWidth={1.6} />
            <h2 className="mt-3 mb-0 text-2xl" id="m4-files-heading">
              {copy.documents.files}
            </h2>
          </header>
          {document.files.length === 0 && !previewArtifactId ? (
            <p className="m-0 text-sm text-muted-foreground">
              {copy.documents.noFiles}
            </p>
          ) : (
            <div className="border-t border-[var(--ink)]">
              {previewArtifactId ? (
                <article className="grid gap-4 border-b border-[var(--line)] py-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center">
                  <div className="min-w-0">
                    <p className="m-0 text-sm font-bold">preview.html</p>
                    <p className="mt-1 mb-0 font-mono text-xs text-muted-foreground">
                      {copy.documents.fileRoles.preview} ·{" "}
                      {shortId(previewArtifactId)}
                    </p>
                  </div>
                  <Button
                    className={m4SecondaryButtonClass}
                    disabled={
                      working === `download-preview:${previewArtifactId}`
                    }
                    onClick={() =>
                      void downloadPreviewArtifact(previewArtifactId)
                    }
                    type="button"
                  >
                    <Download aria-hidden="true" size={17} />
                    {copy.documents.download}
                  </Button>
                </article>
              ) : null}
              {document.files.map((file) => (
                <article
                  className="grid gap-4 border-b border-[var(--line)] py-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center"
                  key={file.id}
                >
                  <div className="min-w-0">
                    <p className="m-0 text-sm font-bold [overflow-wrap:anywhere]">
                      {file.filename}
                    </p>
                    <p className="mt-1 mb-0 font-mono text-xs text-muted-foreground">
                      {copy.documents.fileRoles[file.role] ?? file.role} · v
                      {file.version} · {formatBytes(file.byte_size, locale)}
                    </p>
                    <code className="mt-2 block truncate text-[0.68rem] text-muted-foreground">
                      {file.checksum_sha256}
                    </code>
                  </div>
                  <Button
                    className={m4SecondaryButtonClass}
                    disabled={working === `download:${file.id}`}
                    onClick={() => void downloadFile(file.id)}
                    type="button"
                  >
                    <Download aria-hidden="true" size={17} />
                    {copy.documents.download}
                  </Button>
                </article>
              ))}
            </div>
          )}
        </div>
      </section>

      <section aria-labelledby="m4-jobs-heading" className={m4SectionClass}>
        <div className="grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)]">
          <header>
            <History aria-hidden="true" size={24} strokeWidth={1.6} />
            <h2 className="mt-3 mb-0 text-2xl" id="m4-jobs-heading">
              {copy.documents.jobHistory}
            </h2>
          </header>
          {document.jobs.length === 0 ? (
            <p className="m-0 text-sm text-muted-foreground">
              {copy.documents.noJobs}
            </p>
          ) : (
            <ol className="m-0 list-none border-t border-[var(--ink)] p-0">
              {document.jobs.map((job, index) => (
                <li
                  className="grid gap-3 border-b border-[var(--line)] py-4 sm:grid-cols-[3rem_minmax(0,1fr)_auto] sm:items-center"
                  key={job.job_id}
                >
                  <span className="font-sans text-2xl font-semibold text-muted-foreground">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <p className="m-0 font-mono text-xs">{job.job_id}</p>
                    <p className="mt-1 mb-0 text-xs text-muted-foreground">
                      {copy.documents.renderAttempts}: {job.attempt_count} ·{" "}
                      {formatDate(job.updated_at, locale)}
                    </p>
                    {job.failure_code ? (
                      <p className="mt-1 mb-0 text-xs font-bold text-[var(--rust)]">
                        {job.failure_code}
                      </p>
                    ) : null}
                  </div>
                  <M4StatusPill
                    label={copy.documents.jobStatuses[job.status] ?? job.status}
                    status={job.status}
                  />
                </li>
              ))}
            </ol>
          )}
        </div>
      </section>

      <section aria-labelledby="m4-lineage-heading" className={m4SectionClass}>
        <div className="grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)]">
          <header>
            <Split aria-hidden="true" size={24} strokeWidth={1.6} />
            <h2 className="mt-3 mb-0 text-2xl" id="m4-lineage-heading">
              {copy.documents.lineage}
            </h2>
          </header>
          <div className="grid gap-4">
            {document.supersedes_document_id ||
            document.superseded_by_document_id ? (
              <div className="grid gap-3 sm:grid-cols-2">
                {document.supersedes_document_id ? (
                  <a
                    className={`${m4SecondaryButtonClass} no-underline`}
                    href={`/documents/${document.supersedes_document_id}${runtime.previewMode ? "?preview=m4" : ""}`}
                  >
                    {copy.documents.supersede} ·{" "}
                    {shortId(document.supersedes_document_id)}
                  </a>
                ) : null}
                {document.superseded_by_document_id ? (
                  <a
                    className={`${m4SecondaryButtonClass} no-underline`}
                    href={`/documents/${document.superseded_by_document_id}${runtime.previewMode ? "?preview=m4" : ""}`}
                  >
                    {copy.documents.openDocument} ·{" "}
                    {shortId(document.superseded_by_document_id)}
                  </a>
                ) : null}
              </div>
            ) : (
              <p className="m-0 text-sm text-muted-foreground">
                {copy.documents.noLineage}
              </p>
            )}
            <details className="border-y border-[var(--line)] py-3">
              <summary className="min-h-11 cursor-pointer font-bold">
                {copy.documents.snapshot}
              </summary>
              <div className="mt-3">
                <JsonSnapshot value={document.version_snapshot} />
              </div>
            </details>
            <dl className="m-0 grid gap-2 font-mono text-xs text-muted-foreground">
              <div>
                <dt className="inline font-bold">
                  {copy.documents.checksum}:{" "}
                </dt>
                <dd className="inline break-all">
                  {document.version_snapshot_checksum ?? "—"}
                </dd>
              </div>
              <div>
                <dt className="inline font-bold">Render: </dt>
                <dd className="inline break-all">
                  {document.render_input_checksum}
                </dd>
              </div>
            </dl>
          </div>
        </div>
      </section>

      <section
        aria-labelledby="m4-signed-upload-heading"
        className={m4SectionClass}
      >
        <h2 className="mb-5 text-2xl" id="m4-signed-upload-heading">
          {copy.documents.signedUpload}
        </h2>
        {runtime.previewMode ? (
          <div className="grid min-h-32 place-items-center border-y border-dashed border-[var(--line)] p-5 text-center text-sm text-muted-foreground">
            <FileCheck2 aria-hidden="true" size={26} />
            <p className="m-0 max-w-lg">{copy.documents.markSignedHint}</p>
          </div>
        ) : (
          <LegalOriginalUpload
            canCreateLegal={false}
            canUploadSigned={true}
            copy={legalOriginalMessages[locale]}
            documents={[
              {
                id: document.id,
                status: document.status,
                watermark:
                  document.official_number ?? document.document_type_key,
              },
            ]}
            locale={locale}
            workspaceId={runtime.selectedWorkspaceId}
          />
        )}
      </section>

      <section aria-labelledby="m4-actions-heading" className={m4SectionClass}>
        <div className="grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)]">
          <header>
            <ShieldAlert aria-hidden="true" size={24} strokeWidth={1.6} />
            <h2 className="mt-3 mb-0 text-2xl" id="m4-actions-heading">
              {copy.documents.status}
            </h2>
          </header>
          <div>
            <ReasonCommand
              action={(reason) => mutate("retry-render", reason)}
              copy={copy}
              disabled={!runtime.canWrite || !actionEligibility.retryRender}
              heading={copy.documents.retryRender}
              hint={copy.documents.renderFailed}
              icon={<RefreshCcw aria-hidden="true" size={17} />}
              working={working === "retry-render"}
            />
            <ReasonCommand
              action={(reason) => mutate("mark-signed", reason)}
              copy={copy}
              disabled={!runtime.canWrite || !actionEligibility.markSigned}
              heading={copy.documents.markSigned}
              hint={copy.documents.markSignedHint}
              icon={<FileCheck2 aria-hidden="true" size={17} />}
              working={working === "mark-signed"}
            />
            <ReasonCommand
              action={(reason) => mutate("void", reason)}
              copy={copy}
              danger
              disabled={!runtime.canWrite || !actionEligibility.void}
              heading={copy.documents.voidAction}
              hint={copy.documents.voidHint}
              icon={<XOctagon aria-hidden="true" size={17} />}
              working={working === "void"}
            />
            <details className="border-t border-[var(--line)] py-5">
              <summary className="min-h-11 cursor-pointer text-base font-bold">
                {copy.documents.supersede}
              </summary>
              <p className="mt-2 mb-5 text-sm leading-6 text-muted-foreground">
                {copy.documents.supersedeHint}
              </p>
              <ReasonCommand
                action={supersede}
                copy={copy}
                disabled={
                  !runtime.canWrite || !actionEligibility.supersede || !type
                }
                heading={copy.documents.supersede}
                hint={copy.documents.confirmAllocationHint}
                icon={<Split aria-hidden="true" size={17} />}
                working={working === "supersede"}
              >
                <div className="grid gap-4 sm:grid-cols-2">
                  <label className={m4LabelClass}>
                    {copy.documents.templateVersionId}
                    <Input
                      className={m4FieldClass}
                      onChange={(event) =>
                        setSupersedeTemplateId(event.target.value)
                      }
                      required
                      value={supersedeTemplateId}
                    />
                  </label>
                  <label className={m4LabelClass}>
                    {copy.documents.documentDate}
                    <Input
                      className={m4FieldClass}
                      onChange={(event) => setSupersedeDate(event.target.value)}
                      required
                      type="date"
                      value={supersedeDate}
                    />
                  </label>
                  <label className={m4LabelClass}>
                    {copy.documents.intendedSignatureDate}
                    <Input
                      className={m4FieldClass}
                      onChange={(event) =>
                        setSupersedeSignatureDate(event.target.value)
                      }
                      type="date"
                      value={supersedeSignatureDate}
                    />
                  </label>
                </div>
                <SchemaFieldInputs
                  copy={copy}
                  disabled={working !== null}
                  fields={fields}
                  onChange={(key, value) =>
                    setSupersedeValues((current) => ({
                      ...current,
                      [key]: value,
                    }))
                  }
                  values={supersedeValues}
                />
                <div className="grid gap-4 sm:grid-cols-2">
                  <label className={m4LabelClass}>
                    {copy.documents.calculationEvidence}
                    <Textarea
                      className={m4TextAreaClass}
                      onChange={(event) =>
                        setSupersedeCalculationEvidence(event.target.value)
                      }
                      rows={4}
                      value={supersedeCalculationEvidence}
                    />
                  </label>
                  <label className={m4LabelClass}>
                    {copy.documents.taxEvidence}
                    <Textarea
                      className={m4TextAreaClass}
                      onChange={(event) =>
                        setSupersedeTaxEvidence(event.target.value)
                      }
                      rows={4}
                      value={supersedeTaxEvidence}
                    />
                  </label>
                </div>
              </ReasonCommand>
            </details>
          </div>
        </div>
      </section>
    </div>
  );
}

export function M4DocumentWorkbench({
  documentId,
  locale,
  previewMode,
  view,
}: {
  readonly documentId?: string;
  readonly locale: Locale;
  readonly previewMode: boolean;
  readonly view: M4DocumentView;
}) {
  const copy = m4Messages[locale];
  const detail = view === "detail";
  return (
    <M4OperatorRuntime
      attentionCount={
        detail
          ? 1
          : previewDocuments.filter((document) =>
              ["failed", "generation_failed"].includes(document.status),
            ).length
      }
      copy={copy}
      current="documents"
      eyebrow={
        detail ? copy.documents.detailEyebrow : copy.documents.listEyebrow
      }
      locale={locale}
      previewMode={previewMode}
      summary={detail ? copy.documents.detailSummary : copy.documents.summary}
      title={detail ? copy.documents.detailHeading : copy.documents.heading}
    >
      {(runtime) =>
        detail && documentId ? (
          <DocumentDetailSurface
            copy={copy}
            documentId={documentId}
            key={runtime.selectedWorkspaceId}
            locale={locale}
            runtime={runtime}
          />
        ) : (
          <DocumentListSurface
            copy={copy}
            key={runtime.selectedWorkspaceId}
            locale={locale}
            runtime={runtime}
          />
        )
      }
    </M4OperatorRuntime>
  );
}
