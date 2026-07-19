"use client";

import {
  AlertTriangle,
  Download,
  FileDown,
  FileSpreadsheet,
  Filter,
  LoaderCircle,
  RefreshCcw,
  ShieldCheck,
} from "lucide-react";
import {
  type FormEvent,
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import { Button, Input, NativeSelect, Textarea } from "@vynlo/ui-web";

import type { Locale } from "../i18n/messages";
import { m4Messages, type M4Messages } from "../i18n/m4-messages";
import { formatM3MinorAmount } from "../lib/m3-money";
import {
  localizedM4Label,
  m4Query,
  newM4IdempotencyKey,
  parseM4JsonObject,
  requestM4Json,
  type M4DealReportRow,
  type M4DownloadGrant,
  type M4ExportDefinition,
  type M4ExportRun,
  type M4ExportRunRequest,
  type M4InventoryAgingRow,
  type M4InventoryGrossRow,
  type M4LeadReportRow,
  type M4ReportRow,
} from "../lib/m4-api-client";
import {
  M4InlineStatus,
  M4OperatorRuntime,
  M4StatusPill,
  m4FieldClass,
  m4LabelClass,
  m4PrimaryButtonClass,
  m4SecondaryButtonClass,
  m4SectionClass,
  m4TextAreaClass,
  type M4OperatorRuntimeState,
} from "./m4-operator-runtime";

type ReportKey = "inventory-aging" | "inventory-gross" | "leads" | "deals";

const checksum = "f".repeat(64);
const previewDefinitions: readonly M4ExportDefinition[] = [
  {
    active_version_id: "42000000-0000-4000-8000-000000000401",
    columns: ["stock_number", "age_days", "cost_amount_minor"],
    filter_schema: {},
    formats: ["csv", "xlsx"],
    id: "42000000-0000-4000-8000-000000000402",
    key: "inventory_aging",
    labels: { en: "Inventory aging", fr: "Âge de l’inventaire" },
    maximum_rows: 10_000,
    permission_key: "reports.read",
    sensitivity: "standard",
    step_up_required: false,
    version_checksum: checksum,
  },
  {
    active_version_id: "42000000-0000-4000-8000-000000000403",
    columns: ["stock_number", "revenue_amount_minor", "gross_amount_minor"],
    filter_schema: {},
    formats: ["csv", "xlsx"],
    id: "42000000-0000-4000-8000-000000000404",
    key: "inventory_gross",
    labels: { en: "Inventory gross", fr: "Marge d’inventaire" },
    maximum_rows: 10_000,
    permission_key: "exports.run_sensitive",
    sensitivity: "sensitive",
    step_up_required: true,
    version_checksum: "e".repeat(64),
  },
  {
    active_version_id: "42000000-0000-4000-8000-000000000405",
    columns: ["created_at", "status", "source_key"],
    filter_schema: {},
    formats: ["csv", "xlsx"],
    id: "42000000-0000-4000-8000-000000000406",
    key: "leads",
    labels: { en: "Leads", fr: "Prospects" },
    maximum_rows: 25_000,
    permission_key: "reports.read",
    sensitivity: "standard",
    step_up_required: false,
    version_checksum: "d".repeat(64),
  },
  {
    active_version_id: "42000000-0000-4000-8000-000000000407",
    columns: ["created_at", "status", "total_amount_minor"],
    filter_schema: {},
    formats: ["csv", "xlsx"],
    id: "42000000-0000-4000-8000-000000000408",
    key: "deals",
    labels: { en: "Deals", fr: "Dossiers" },
    maximum_rows: 25_000,
    permission_key: "reports.read",
    sensitivity: "standard",
    step_up_required: false,
    version_checksum: "c".repeat(64),
  },
];

const previewReports: Readonly<Record<ReportKey, readonly M4ReportRow[]>> = {
  "inventory-aging": [
    {
      acquired_on: "2026-03-08",
      age_days: 130,
      cost_amount_minor: "2875000",
      currency_code: "CAD",
      inventory_unit_id: "42000000-0000-4000-8000-000000000409",
      location_id: "42000000-0000-4000-8000-000000000410",
      make: "Polestar",
      model: "2",
      model_year: 2024,
      stock_number: "STK-1042",
    } satisfies M4InventoryAgingRow,
    {
      acquired_on: "2026-05-28",
      age_days: 49,
      cost_amount_minor: "1995000",
      currency_code: "CAD",
      inventory_unit_id: "42000000-0000-4000-8000-000000000411",
      location_id: "42000000-0000-4000-8000-000000000410",
      make: "Mazda",
      model: "CX-5",
      model_year: 2023,
      stock_number: "STK-1091",
    } satisfies M4InventoryAgingRow,
  ],
  "inventory-gross": [
    {
      closed_at: "2026-07-15T18:20:00.000Z",
      cost_amount_minor: "2415000",
      currency_code: "CAD",
      deal_id: "42000000-0000-4000-8000-000000000412",
      gross_amount_minor: "235000",
      inventory_unit_id: "42000000-0000-4000-8000-000000000413",
      revenue_amount_minor: "2650000",
      stock_number: "STK-1078",
    } satisfies M4InventoryGrossRow,
  ],
  leads: [
    {
      converted_deal_id: "42000000-0000-4000-8000-000000000412",
      created_at: "2026-07-12T14:10:00.000Z",
      id: "42000000-0000-4000-8000-000000000414",
      last_activity_at: "2026-07-16T09:40:00.000Z",
      owner_membership_id: "42000000-0000-4000-8000-000000000415",
      source_key: "website",
      status: "converted",
    } satisfies M4LeadReportRow,
  ],
  deals: [
    {
      created_at: "2026-07-12T15:00:00.000Z",
      currency_code: "CAD",
      deal_type_key: "retail_cash",
      id: "42000000-0000-4000-8000-000000000412",
      owner_membership_id: "42000000-0000-4000-8000-000000000415",
      status: "contracted",
      total_amount_minor: "2650000",
      updated_at: "2026-07-15T18:20:00.000Z",
    } satisfies M4DealReportRow,
  ],
};

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

function formatDate(value: string, locale: Locale): string {
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

function reportLabel(copy: M4Messages, report: ReportKey): string {
  switch (report) {
    case "inventory-aging":
      return copy.exports.aging;
    case "inventory-gross":
      return copy.exports.gross;
    case "leads":
      return copy.exports.leads;
    case "deals":
      return copy.exports.deals;
  }
}

function reportTitle(row: M4ReportRow): string {
  if ("stock_number" in row && "make" in row) {
    return `${row.model_year} ${row.make} ${row.model}`;
  }
  if ("stock_number" in row) return row.stock_number;
  if ("source_key" in row) return `${row.source_key} · ${row.id.slice(0, 8)}`;
  return `${row.deal_type_key} · ${row.id.slice(0, 8)}`;
}

function reportEntries(
  row: M4ReportRow,
  locale: Locale,
): readonly Readonly<{ key: string; value: string }>[] {
  const currency = "currency_code" in row ? row.currency_code : null;
  return Object.entries(row).flatMap(([key, value]) => {
    if (key === "currency_code" || value === null) return [];
    if (
      key.endsWith("_amount_minor") &&
      currency &&
      typeof value === "string"
    ) {
      return [{ key, value: formatM3MinorAmount(value, currency, locale) }];
    }
    if (
      (key.endsWith("_at") || key.endsWith("_on")) &&
      typeof value === "string"
    ) {
      return [{ key, value: formatDate(value, locale) }];
    }
    return [{ key, value: String(value) }];
  });
}

function ReportRows({
  copy,
  locale,
  rows,
}: {
  readonly copy: M4Messages;
  readonly locale: Locale;
  readonly rows: readonly M4ReportRow[];
}) {
  if (rows.length === 0) {
    return (
      <p className="border-y border-[var(--line)] py-10 text-sm text-muted-foreground">
        {copy.exports.emptyReport}
      </p>
    );
  }
  return (
    <div className="border-t border-[var(--ink)]">
      {rows.map((row) => {
        const id = "inventory_unit_id" in row ? row.inventory_unit_id : row.id;
        return (
          <article
            className="grid gap-4 border-b border-[var(--line)] py-5 lg:grid-cols-[15rem_minmax(0,1fr)]"
            key={id}
          >
            <header>
              <h3 className="m-0 text-lg tracking-[-0.02em]">
                {reportTitle(row)}
              </h3>
              <p className="mt-1 mb-0 font-mono text-xs text-muted-foreground">
                {id.slice(0, 8)}
              </p>
            </header>
            <dl className="m-0 grid min-w-0 gap-x-6 sm:grid-cols-2">
              {reportEntries(row, locale).map(({ key, value }) => (
                <div
                  className="grid grid-cols-[minmax(7rem,0.8fr)_minmax(0,1.2fr)] gap-3 border-b border-[var(--line)] py-2 text-sm"
                  key={key}
                >
                  <dt className="font-semibold text-muted-foreground">
                    {copy.exports.reportFields[key] ?? key}
                  </dt>
                  <dd className="m-0 min-w-0 text-right font-mono [overflow-wrap:anywhere]">
                    {value}
                  </dd>
                </div>
              ))}
            </dl>
          </article>
        );
      })}
    </div>
  );
}

function ExportSurface({
  copy,
  locale,
  runtime,
}: {
  readonly copy: M4Messages;
  readonly locale: Locale;
  readonly runtime: M4OperatorRuntimeState;
}) {
  const [definitions, setDefinitions] = useState<readonly M4ExportDefinition[]>(
    [],
  );
  const [selectedKey, setSelectedKey] = useState("");
  const [format, setFormat] = useState<"csv" | "xlsx">("csv");
  const [filters, setFilters] = useState("{}");
  const [reason, setReason] = useState("");
  const [run, setRun] = useState<M4ExportRun | null>(null);
  const [report, setReport] = useState<ReportKey>("inventory-aging");
  const [reportRows, setReportRows] = useState<readonly M4ReportRow[]>([]);
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [locationId, setLocationId] = useState("");
  const [loadingDefinitions, setLoadingDefinitions] = useState(true);
  const [loadingReport, setLoadingReport] = useState(true);
  const [working, setWorking] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState("");
  const exportCommand = useRef<
    Readonly<{ fingerprint: string; idempotencyKey: string }> | undefined
  >(undefined);

  const selected =
    definitions.find((definition) => definition.key === selectedKey) ??
    definitions[0];

  const loadDefinitions = useCallback(async () => {
    setLoadingDefinitions(true);
    setError(null);
    try {
      const next = runtime.previewMode
        ? previewDefinitions
        : await requestM4Json<readonly M4ExportDefinition[]>({
            context: runtime.apiContext,
            path: "/api/v1/export-definitions",
          });
      setDefinitions(next);
      setSelectedKey((current) =>
        next.some((item) => item.key === current)
          ? current
          : (next[0]?.key ?? ""),
      );
    } catch (loadError) {
      setError(safeError(copy, loadError));
    } finally {
      setLoadingDefinitions(false);
    }
  }, [copy, runtime.apiContext, runtime.previewMode]);

  const loadReport = useCallback(async () => {
    setLoadingReport(true);
    setError(null);
    try {
      const next = runtime.previewMode
        ? previewReports[report]
        : await requestM4Json<readonly M4ReportRow[]>({
            context: runtime.apiContext,
            path: m4Query(`/api/v1/reports/${report}`, {
              date_from: dateFrom || undefined,
              date_to: dateTo || undefined,
              limit: "100",
              location_id: locationId || undefined,
            }),
          });
      setReportRows(next);
    } catch (loadError) {
      setError(safeError(copy, loadError));
    } finally {
      setLoadingReport(false);
    }
  }, [
    copy,
    dateFrom,
    dateTo,
    locationId,
    report,
    runtime.apiContext,
    runtime.previewMode,
  ]);

  useEffect(() => {
    let active = true;
    queueMicrotask(() => {
      if (active) void loadDefinitions();
    });
    return () => {
      active = false;
    };
  }, [loadDefinitions]);
  useEffect(() => {
    let active = true;
    queueMicrotask(() => {
      if (active) void loadReport();
    });
    return () => {
      active = false;
    };
  }, [loadReport]);

  useEffect(() => {
    if (!run || !["queued", "retry_wait", "running"].includes(run.status))
      return;
    let stopped = false;
    const timer = window.setTimeout(
      () => {
        if (stopped) return;
        if (runtime.previewMode) {
          setRun((current) =>
            current
              ? {
                  ...current,
                  export_file_id: "42000000-0000-4000-8000-000000000416",
                  generated_checksum: checksum,
                  row_count: 2,
                  status: "generated",
                }
              : current,
          );
          return;
        }
        void requestM4Json<M4ExportRun>({
          context: runtime.apiContext,
          path: `/api/v1/export-runs/${encodeURIComponent(run.export_run_id)}`,
        })
          .then((next) => {
            if (!stopped) setRun(next);
          })
          .catch((pollError) => {
            if (!stopped) setError(safeError(copy, pollError));
          });
      },
      runtime.previewMode ? 900 : 2_500,
    );
    return () => {
      stopped = true;
      window.clearTimeout(timer);
    };
  }, [copy, run, runtime.apiContext, runtime.previewMode]);

  async function generate(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    if (!selected) return;
    setWorking("generate");
    setError(null);
    setNotice("");
    try {
      const parsedFilters = parseM4JsonObject(filters);
      const fingerprint = JSON.stringify({
        definitionKey: selected.key,
        filters: parsedFilters,
        format: effectiveFormat,
        locale,
        reason,
      });
      const command =
        exportCommand.current?.fingerprint === fingerprint
          ? exportCommand.current
          : {
              fingerprint,
              idempotencyKey: newM4IdempotencyKey("export-run"),
            };
      exportCommand.current = command;
      const request = runtime.previewMode
        ? ({
            audit_event_id: "42000000-0000-4000-8000-000000000417",
            expires_at: "2026-07-17T18:00:00.000Z",
            export_run_id: "42000000-0000-4000-8000-000000000418",
            job_id: "42000000-0000-4000-8000-000000000419",
            job_status: "queued",
            replayed: false,
            run_status: "queued",
          } satisfies M4ExportRunRequest)
        : await requestM4Json<M4ExportRunRequest>({
            body: {
              filters: parsedFilters,
              format: effectiveFormat,
              locale,
              reason,
            },
            context: runtime.apiContext,
            idempotencyKey: command.idempotencyKey,
            method: "POST",
            path: `/api/v1/exports/${encodeURIComponent(selected.key)}/runs`,
          });
      setRun({
        created_at: new Date().toISOString(),
        expires_at: request.expires_at,
        export_definition_key: selected.key,
        export_file_id: null,
        export_run_id: request.export_run_id,
        export_version_id: selected.active_version_id,
        failure_code: null,
        generated_checksum: null,
        job_id: request.job_id,
        locale,
        outbox_event_id: null,
        replayed: request.replayed,
        requested_format: effectiveFormat,
        row_count: null,
        status: request.run_status,
      });
      setNotice(copy.exports.runQueued);
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

  async function downloadRun(): Promise<void> {
    if (!run) return;
    setWorking("download");
    setError(null);
    try {
      if (runtime.previewMode) {
        setNotice(copy.exports.generated);
      } else {
        const grant = await requestM4Json<M4DownloadGrant>({
          context: runtime.apiContext,
          path: `/api/v1/export-runs/${encodeURIComponent(run.export_run_id)}/download`,
        });
        window.location.assign(grant.download.url);
      }
    } catch (downloadError) {
      setError(safeError(copy, downloadError));
    } finally {
      setWorking(null);
    }
  }

  const formats: readonly ("csv" | "xlsx")[] = selected?.formats ?? ["csv"];
  const effectiveFormat = formats.includes(format)
    ? format
    : (formats[0] ?? "csv");

  function selectDefinition(key: string): void {
    const next = definitions.find((definition) => definition.key === key);
    setSelectedKey(key);
    if (next && !next.formats.includes(format)) {
      setFormat(next.formats[0] ?? "csv");
    }
  }

  return (
    <div className="mx-auto max-w-[90rem] px-4 sm:px-6 lg:px-8">
      {error ? (
        <div
          className="mt-5 flex items-start gap-3 rounded-[var(--radius-panel)] border border-destructive/40 bg-destructive/5 p-4"
          role="alert"
        >
          <AlertTriangle aria-hidden="true" className="mt-0.5" size={18} />
          <p className="m-0 text-sm font-semibold">{error}</p>
        </div>
      ) : null}
      {notice ? <M4InlineStatus message={notice} /> : null}

      <section aria-labelledby="m4-reports-heading" className={m4SectionClass}>
        <div className="grid gap-7 lg:grid-cols-[15rem_minmax(0,1fr)]">
          <header>
            <FileSpreadsheet aria-hidden="true" size={25} strokeWidth={1.6} />
            <h2 className="mt-3 mb-0 text-2xl" id="m4-reports-heading">
              {copy.exports.reportHeading}
            </h2>
            <p className="mt-3 mb-0 text-sm leading-6 text-muted-foreground">
              {copy.exports.reportHint}
            </p>
          </header>
          <div className="min-w-0">
            <div
              aria-label={copy.exports.reportHeading}
              className="grid grid-cols-2 border border-[var(--line)] sm:grid-cols-4"
              role="tablist"
            >
              {(
                [
                  "inventory-aging",
                  "inventory-gross",
                  "leads",
                  "deals",
                ] as const
              ).map((key) => (
                <Button
                  aria-selected={report === key}
                  className={`min-h-12 border-0 px-2 text-xs font-bold ${report === key ? "bg-[var(--ink)] text-[var(--paper)]" : "bg-[var(--surface)] text-[var(--ink)] hover:bg-[var(--paper)]"}`}
                  key={key}
                  onClick={() => setReport(key)}
                  role="tab"
                  type="button"
                >
                  {reportLabel(copy, key)}
                </Button>
              ))}
            </div>
            <form
              className="grid gap-4 border-b border-[var(--line)] py-5 sm:grid-cols-3"
              onSubmit={(event) => {
                event.preventDefault();
                void loadReport();
              }}
            >
              <label className={m4LabelClass}>
                {copy.exports.dateFrom}
                <Input
                  className={m4FieldClass}
                  onChange={(event) => setDateFrom(event.target.value)}
                  type="date"
                  value={dateFrom}
                />
              </label>
              <label className={m4LabelClass}>
                {copy.exports.dateTo}
                <Input
                  className={m4FieldClass}
                  onChange={(event) => setDateTo(event.target.value)}
                  type="date"
                  value={dateTo}
                />
              </label>
              <label className={m4LabelClass}>
                {copy.exports.locationId}
                <Input
                  className={m4FieldClass}
                  onChange={(event) => setLocationId(event.target.value)}
                  value={locationId}
                />
              </label>
              <Button
                className={`${m4SecondaryButtonClass} justify-self-start sm:col-span-3`}
                disabled={loadingReport}
                type="submit"
              >
                <Filter aria-hidden="true" size={17} />
                {copy.exports.refresh}
              </Button>
            </form>
            {loadingReport ? (
              <p
                className="flex min-h-32 items-center justify-center gap-3 text-sm font-semibold"
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
              <ReportRows copy={copy} locale={locale} rows={reportRows} />
            )}
          </div>
        </div>
      </section>

      <section aria-labelledby="m4-exports-heading" className={m4SectionClass}>
        <div className="grid gap-7 lg:grid-cols-[15rem_minmax(0,1fr)]">
          <header>
            <FileDown aria-hidden="true" size={25} strokeWidth={1.6} />
            <h2 className="mt-3 mb-0 text-2xl" id="m4-exports-heading">
              {copy.exports.exportHeading}
            </h2>
            <p className="mt-3 mb-0 text-sm leading-6 text-muted-foreground">
              {copy.exports.summary}
            </p>
          </header>
          <div className="min-w-0">
            {loadingDefinitions ? (
              <p
                className="flex min-h-32 items-center justify-center gap-3 text-sm font-semibold"
                role="status"
              >
                <LoaderCircle
                  aria-hidden="true"
                  className="animate-spin motion-reduce:animate-none"
                  size={18}
                />
                {copy.common.loading}
              </p>
            ) : definitions.length === 0 ? (
              <p className="m-0 border-y border-[var(--line)] py-10 text-sm text-muted-foreground">
                {copy.exports.emptyDefinitions}
              </p>
            ) : (
              <>
                <div className="border-t border-[var(--ink)]">
                  {definitions.map((definition) => (
                    <article
                      className={`grid gap-3 border-b border-[var(--line)] py-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center ${selected?.id === definition.id ? "bg-[color-mix(in_srgb,var(--signal)_12%,transparent)]" : ""}`}
                      key={definition.id}
                    >
                      <Button
                        className="min-h-11 w-full min-w-0 flex-col items-start justify-center whitespace-normal border-0 bg-transparent p-0 text-left"
                        onClick={() => selectDefinition(definition.key)}
                        type="button"
                        variant="ghost"
                      >
                        <strong className="block text-base">
                          {localizedM4Label(
                            definition.labels,
                            locale,
                            definition.key,
                          )}
                        </strong>
                        <span className="mt-1 block font-mono text-xs text-muted-foreground [overflow-wrap:anywhere]">
                          {definition.key} · {definition.columns.length}{" "}
                          {copy.exports.columns.toLowerCase()}
                        </span>
                      </Button>
                      <div className="flex flex-wrap gap-2 sm:justify-end">
                        <M4StatusPill
                          label={definition.sensitivity}
                          status={
                            definition.step_up_required ? "approved" : "active"
                          }
                        />
                        {definition.step_up_required ? (
                          <span className="inline-flex items-center gap-2 text-xs font-bold text-[var(--rust)]">
                            <ShieldCheck aria-hidden="true" size={15} />
                            {copy.exports.stepUp}
                          </span>
                        ) : null}
                      </div>
                    </article>
                  ))}
                </div>
                {selected ? (
                  <form
                    className="mt-6 grid w-full min-w-0 max-w-full grid-cols-[minmax(0,1fr)] gap-5 overflow-hidden"
                    onSubmit={(event) => void generate(event)}
                  >
                    <div className="grid w-full min-w-0 max-w-full gap-4 overflow-hidden sm:grid-cols-2">
                      <label className={m4LabelClass}>
                        {copy.exports.definition}
                        <NativeSelect
                          className={m4FieldClass}
                          onChange={(event) =>
                            selectDefinition(event.target.value)
                          }
                          value={selected.key}
                        >
                          {definitions.map((definition) => (
                            <option key={definition.key} value={definition.key}>
                              {localizedM4Label(
                                definition.labels,
                                locale,
                                definition.key,
                              )}
                            </option>
                          ))}
                        </NativeSelect>
                      </label>
                      <label className={m4LabelClass}>
                        {copy.exports.format}
                        <NativeSelect
                          className={m4FieldClass}
                          onChange={(event) =>
                            setFormat(event.target.value as "csv" | "xlsx")
                          }
                          value={effectiveFormat}
                        >
                          {formats.map((value) => (
                            <option key={value} value={value}>
                              {value.toUpperCase()}
                            </option>
                          ))}
                        </NativeSelect>
                      </label>
                      <label className={`${m4LabelClass} sm:col-span-2`}>
                        {copy.exports.filters}
                        <Textarea
                          className={m4TextAreaClass}
                          onChange={(event) => setFilters(event.target.value)}
                          rows={5}
                          value={filters}
                        />
                      </label>
                      <label className={`${m4LabelClass} sm:col-span-2`}>
                        {copy.exports.reason}
                        <Textarea
                          className={m4TextAreaClass}
                          onChange={(event) => setReason(event.target.value)}
                          required
                          rows={3}
                          value={reason}
                        />
                      </label>
                    </div>
                    <dl className="m-0 grid w-full min-w-0 max-w-full gap-2 overflow-hidden border-y border-[var(--line)] py-3 text-xs sm:grid-cols-3">
                      <div className="min-w-0">
                        <dt className="font-bold text-muted-foreground">
                          {copy.exports.permission}
                        </dt>
                        <dd className="m-0 mt-1 break-all font-mono">
                          {selected.permission_key}
                        </dd>
                      </div>
                      <div className="min-w-0">
                        <dt className="font-bold text-muted-foreground">
                          {copy.exports.maximumRows}
                        </dt>
                        <dd className="m-0 mt-1 font-mono">
                          {selected.maximum_rows.toLocaleString(locale)}
                        </dd>
                      </div>
                      <div className="min-w-0">
                        <dt className="font-bold text-muted-foreground">
                          {copy.configuration.checksum}
                        </dt>
                        <dd className="m-0 mt-1 truncate font-mono">
                          {selected.version_checksum}
                        </dd>
                      </div>
                    </dl>
                    <Button
                      className={`${m4PrimaryButtonClass} justify-self-start`}
                      disabled={
                        !runtime.canWrite ||
                        working !== null ||
                        reason.trim().length === 0
                      }
                      type="submit"
                    >
                      {working === "generate" ? (
                        <LoaderCircle
                          aria-hidden="true"
                          className="animate-spin motion-reduce:animate-none"
                          size={17}
                        />
                      ) : (
                        <FileDown aria-hidden="true" size={17} />
                      )}
                      {copy.exports.generate}
                    </Button>
                  </form>
                ) : null}
              </>
            )}
          </div>
        </div>
      </section>

      {run ? (
        <section aria-labelledby="m4-run-heading" className={m4SectionClass}>
          <div className="grid gap-7 lg:grid-cols-[15rem_minmax(0,1fr)]">
            <header>
              <RefreshCcw
                aria-hidden="true"
                className={
                  ["queued", "running", "retry_wait"].includes(run.status)
                    ? "animate-spin motion-reduce:animate-none"
                    : ""
                }
                size={24}
                strokeWidth={1.6}
              />
              <h2 className="mt-3 mb-0 text-2xl" id="m4-run-heading">
                {copy.exports.runHeading}
              </h2>
            </header>
            <div className="grid gap-5 border-t border-[var(--ink)] py-4">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h3 className="m-0 text-lg">
                    {run.export_definition_key} ·{" "}
                    {run.requested_format.toUpperCase()}
                  </h3>
                  <p className="mt-1 mb-0 font-mono text-xs text-muted-foreground">
                    {run.export_run_id}
                  </p>
                </div>
                <M4StatusPill
                  label={copy.exports.statuses[run.status] ?? run.status}
                  status={run.status}
                />
              </div>
              <dl className="m-0 grid gap-3 text-sm sm:grid-cols-3">
                <div>
                  <dt className="font-bold text-muted-foreground">
                    {copy.exports.created}
                  </dt>
                  <dd className="m-0 mt-1">
                    {formatDate(run.created_at, locale)}
                  </dd>
                </div>
                <div>
                  <dt className="font-bold text-muted-foreground">
                    {copy.exports.expires}
                  </dt>
                  <dd className="m-0 mt-1">
                    {formatDate(run.expires_at, locale)}
                  </dd>
                </div>
                <div>
                  <dt className="font-bold text-muted-foreground">
                    {copy.exports.rowCount}
                  </dt>
                  <dd className="m-0 mt-1 font-mono">{run.row_count ?? "—"}</dd>
                </div>
              </dl>
              {run.failure_code ? (
                <p className="m-0 rounded-[var(--radius-control)] border border-destructive/40 bg-destructive/5 p-3 text-sm font-bold text-destructive">
                  {run.failure_code}
                </p>
              ) : null}
              {run.status === "generated" ? (
                <Button
                  className={`${m4PrimaryButtonClass} justify-self-start`}
                  disabled={working === "download"}
                  onClick={() => void downloadRun()}
                  type="button"
                >
                  <Download aria-hidden="true" size={17} />
                  {copy.exports.download}
                </Button>
              ) : (
                <p className="m-0 text-sm text-muted-foreground">
                  {copy.exports.runQueued}
                </p>
              )}
            </div>
          </div>
        </section>
      ) : null}
    </div>
  );
}

export function M4ExportsWorkbench({
  locale,
  previewMode,
}: {
  readonly locale: Locale;
  readonly previewMode: boolean;
}) {
  const copy = m4Messages[locale];
  return (
    <M4OperatorRuntime
      attentionCount={
        previewDefinitions.filter((definition) => definition.step_up_required)
          .length
      }
      copy={copy}
      current="exports"
      eyebrow={copy.common.reports}
      locale={locale}
      previewMode={previewMode}
      summary={copy.exports.summary}
      title={copy.exports.heading}
    >
      {(runtime) => (
        <ExportSurface
          copy={copy}
          key={runtime.selectedWorkspaceId}
          locale={locale}
          runtime={runtime}
        />
      )}
    </M4OperatorRuntime>
  );
}
