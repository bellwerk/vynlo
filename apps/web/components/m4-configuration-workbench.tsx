"use client";

import {
  AlertTriangle,
  BadgeCheck,
  Calculator,
  ChevronDown,
  FlaskConical,
  Hash,
  LoaderCircle,
  RefreshCcw,
  Scale,
  ShieldCheck,
} from "lucide-react";
import {
  type FormEvent,
  type ReactNode,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";
import { Button, Input, NativeSelect, Textarea } from "@vynlo/ui-web";

import type { Locale } from "../i18n/messages";
import { m4Messages, type M4Messages } from "../i18n/m4-messages";
import {
  localizedM4Label,
  newM4IdempotencyKey,
  parseM4JsonObject,
  requestM4Json,
  type M4ApprovalRecord,
  type M4ArtifactStatus,
  type M4CalculationDefinition,
  type M4NumberingDefinition,
  type M4TaxPack,
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

const checksumA = "a".repeat(64);
const checksumB = "b".repeat(64);
const checksumC = "c".repeat(64);

const previewNumbering: readonly M4NumberingDefinition[] = [
  {
    active_version_id: "41000000-0000-4000-8000-000000000401",
    created_at: "2026-07-15T15:00:00.000Z",
    id: "41000000-0000-4000-8000-000000000402",
    key: "official_document",
    labels: { en: "Official document", fr: "Document officiel" },
    versions: [
      {
        activated_at: "2026-07-16T10:00:00.000Z",
        approval_record_id: "41000000-0000-4000-8000-000000000403",
        checksum: checksumA,
        id: "41000000-0000-4000-8000-000000000401",
        semantic_version: "1.0.0",
        status: "active",
        version: 1,
      },
    ],
  },
];

const previewCalculations: readonly M4CalculationDefinition[] = [
  {
    active_version_id: "41000000-0000-4000-8000-000000000404",
    id: "41000000-0000-4000-8000-000000000405",
    key: "deal_totals",
    labels: { en: "Deal totals", fr: "Totaux du dossier" },
    versions: [
      {
        checksum: checksumB,
        engine_version: "1.0.0",
        id: "41000000-0000-4000-8000-000000000404",
        semantic_version: "1.0.0",
        status: "active",
        version: 1,
      },
      {
        checksum: "d".repeat(64),
        engine_version: "1.0.0",
        id: "41000000-0000-4000-8000-000000000406",
        semantic_version: "1.1.0",
        status: "test_passed",
        version: 2,
      },
    ],
  },
];

const previewTaxes: readonly M4TaxPack[] = [
  {
    active_versions: [],
    id: "41000000-0000-4000-8000-000000000407",
    key: "tax_candidate",
    labels: { en: "Tax candidate", fr: "Ensemble fiscal candidat" },
    source_kind: "portable_pack",
    versions: [
      {
        checksum: checksumC,
        contexts: ["retail_sale"],
        currency_codes: ["CAD"],
        effective_from: "2026-01-01",
        effective_to: null,
        id: "41000000-0000-4000-8000-000000000408",
        jurisdiction_code: "CA-QC",
        semantic_version: "1.0.0",
        status: "test_passed",
        version: 1,
      },
    ],
  },
];

const previewApprovals: readonly M4ApprovalRecord[] = [
  {
    approval_type: "professional_review",
    artifact_checksum: checksumA,
    artifact_id: "41000000-0000-4000-8000-000000000401",
    artifact_key: "official_document",
    artifact_type: "numbering_definition",
    artifact_version: 1,
    attachment_reference: "evidence://synthetic-numbering-review",
    conditions: {},
    decided_at: "2026-07-16T09:45:00.000Z",
    decision: "approved",
    expires_at: null,
    id: "41000000-0000-4000-8000-000000000403",
    professional_organization: "Independent reviewer",
    professional_role: "Compliance reviewer",
    review_due_at: "2027-07-16T09:45:00.000Z",
    supersedes_approval_id: null,
  },
];

type ArtifactType = "numbering_definition" | "calculation" | "tax_pack";

interface ArtifactTarget {
  readonly checksum: string;
  readonly id: string;
  readonly key: string;
  readonly label: string;
  readonly status: M4ArtifactStatus;
  readonly type: ArtifactType;
  readonly version: number;
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

function formatDate(value: string | null, locale: Locale): string {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.valueOf())
    ? "—"
    : new Intl.DateTimeFormat(locale, {
        dateStyle: "medium",
        timeStyle: "short",
        timeZone: "UTC",
      }).format(date);
}

function VersionRow({
  actionLabel,
  canAction,
  checksum,
  copy,
  detail,
  onAction,
  semanticVersion,
  status,
  version,
  working,
}: {
  readonly actionLabel: string;
  readonly canAction: boolean;
  readonly checksum: string;
  readonly copy: M4Messages;
  readonly detail?: string;
  readonly onAction: (reason: string) => Promise<void>;
  readonly semanticVersion: string;
  readonly status: M4ArtifactStatus;
  readonly version: number;
  readonly working: boolean;
}) {
  const [reason, setReason] = useState("");
  return (
    <article className="grid gap-4 border-b border-[var(--line)] py-4 lg:grid-cols-[minmax(0,1fr)_minmax(15rem,0.7fr)]">
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-2">
          <h4 className="m-0 text-base">v{semanticVersion}</h4>
          <M4StatusPill
            label={copy.configuration.statuses[status] ?? status}
            status={status}
          />
        </div>
        <p className="mt-2 mb-0 font-mono text-xs text-muted-foreground">
          {copy.configuration.version} {version} · {checksum.slice(0, 16)}
        </p>
        {detail ? (
          <p className="mt-2 mb-0 text-xs text-muted-foreground">{detail}</p>
        ) : null}
      </div>
      {canAction ? (
        <form
          className="grid gap-3"
          onSubmit={(event) => {
            event.preventDefault();
            void onAction(reason.trim()).then(() => setReason(""));
          }}
        >
          <label className={m4LabelClass}>
            {copy.configuration.reason}
            <Textarea
              className={m4TextAreaClass}
              disabled={working}
              onChange={(event) => setReason(event.target.value)}
              required
              rows={2}
              value={reason}
            />
          </label>
          <Button
            className={`${m4PrimaryButtonClass} justify-self-start`}
            disabled={working || reason.trim().length === 0}
            type="submit"
          >
            {working ? (
              <LoaderCircle
                aria-hidden="true"
                className="animate-spin motion-reduce:animate-none"
                size={17}
              />
            ) : (
              <ShieldCheck aria-hidden="true" size={17} />
            )}
            {actionLabel}
          </Button>
        </form>
      ) : null}
    </article>
  );
}

function DefinitionSection({
  children,
  description,
  heading,
  icon,
  id,
}: {
  readonly children: ReactNode;
  readonly description: string;
  readonly heading: string;
  readonly icon: ReactNode;
  readonly id: string;
}) {
  return (
    <section aria-labelledby={id} className={m4SectionClass}>
      <div className="grid gap-7 lg:grid-cols-[15rem_minmax(0,1fr)]">
        <header>
          {icon}
          <h2 className="mt-3 mb-0 text-2xl" id={id}>
            {heading}
          </h2>
          <p className="mt-3 mb-0 text-sm leading-6 text-muted-foreground">
            {description}
          </p>
        </header>
        <div className="min-w-0">{children}</div>
      </div>
    </section>
  );
}

function NumberingVersionForm({
  copy,
  definition,
  disabled,
  onCreated,
  runtime,
}: {
  readonly copy: M4Messages;
  readonly definition: M4NumberingDefinition | undefined;
  readonly disabled: boolean;
  readonly onCreated: () => Promise<void>;
  readonly runtime: M4OperatorRuntimeState;
}) {
  const [semanticVersion, setSemanticVersion] = useState("1.0.0");
  const allocationEvent = "official_document_created";
  const [expectedChecksum, setExpectedChecksum] = useState("");
  const [formatPattern, setFormatPattern] = useState(
    "{{prefix}}{{period}}-{{sequence}}",
  );
  const [prefix, setPrefix] = useState("DOC-");
  const [suffix, setSuffix] = useState("");
  const [numericWidth, setNumericWidth] = useState("5");
  const [startingValue, setStartingValue] = useState("1");
  const [increment, setIncrement] = useState("1");
  const [resetPolicy, setResetPolicy] = useState("yearly");
  const [periodAnchor, setPeriodAnchor] = useState("");
  const [periodMonths, setPeriodMonths] = useState("12");
  const [importPolicy, setImportPolicy] = useState("prohibited");
  const [scope, setScope] = useState("workspace");
  const timezone = "UTC";
  const [reason, setReason] = useState("");
  const [working, setWorking] = useState(false);
  const [message, setMessage] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    if (!definition) return;
    setWorking(true);
    setMessage("");
    try {
      const latestVersion = [...definition.versions].sort(
        (left, right) => right.version - left.version,
      )[0];
      if (!runtime.previewMode) {
        await requestM4Json({
          body: {
            allocationEvent,
            expectedLatestVersionId: latestVersion?.id ?? null,
            expectedChecksum,
            formatPattern,
            importPolicy,
            incrementBy: increment,
            labels: definition.labels,
            numericWidth: Number(numericWidth),
            periodAnchor:
              resetPolicy === "configured_period" ? periodAnchor : null,
            periodMonths:
              resetPolicy === "configured_period" ? Number(periodMonths) : null,
            prefix,
            reason,
            resetPolicy,
            scopeType: scope,
            semanticVersion,
            startingValue,
            suffix,
            timezoneName: timezone,
          },
          context: runtime.apiContext,
          idempotencyKey: newM4IdempotencyKey("numbering-version"),
          method: "POST",
          path: `/api/v1/numbering-definitions/${encodeURIComponent(definition.key)}/versions`,
        });
      }
      setMessage(copy.common.saved);
      await onCreated();
    } catch (error) {
      setMessage(
        error instanceof SyntaxError || error instanceof TypeError
          ? copy.documents.fieldInvalidJson
          : safeError(copy, error),
      );
    } finally {
      setWorking(false);
    }
  }

  return (
    <details className="border-b border-[var(--ink)] py-4">
      <summary className="flex min-h-11 cursor-pointer items-center justify-between gap-3 font-bold">
        {copy.configuration.newVersion}
        <ChevronDown aria-hidden="true" size={18} />
      </summary>
      <form
        className="mt-5 grid gap-5"
        onSubmit={(event) => void submit(event)}
      >
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <label className={m4LabelClass}>
            {copy.configuration.semanticVersion}
            <Input
              className={m4FieldClass}
              disabled={disabled || working}
              onChange={(event) => setSemanticVersion(event.target.value)}
              required
              value={semanticVersion}
            />
          </label>
          <label className={`${m4LabelClass} sm:col-span-2`}>
            {copy.configuration.allocationEvent}
            <Input
              className={m4FieldClass}
              disabled
              readOnly
              value={allocationEvent}
            />
          </label>
          <label className={`${m4LabelClass} sm:col-span-2`}>
            {copy.configuration.expectedChecksum}
            <Input
              className={m4FieldClass}
              disabled={disabled || working}
              minLength={64}
              maxLength={64}
              onChange={(event) => setExpectedChecksum(event.target.value)}
              required
              value={expectedChecksum}
            />
          </label>
          <label className={`${m4LabelClass} sm:col-span-2`}>
            {copy.configuration.formatPattern}
            <Input
              className={m4FieldClass}
              disabled={disabled || working}
              onChange={(event) => setFormatPattern(event.target.value)}
              required
              value={formatPattern}
            />
          </label>
          <label className={m4LabelClass}>
            {copy.configuration.prefix}
            <Input
              className={m4FieldClass}
              disabled={disabled || working}
              onChange={(event) => setPrefix(event.target.value)}
              value={prefix}
            />
          </label>
          <label className={m4LabelClass}>
            {copy.configuration.suffix}
            <Input
              className={m4FieldClass}
              disabled={disabled || working}
              onChange={(event) => setSuffix(event.target.value)}
              value={suffix}
            />
          </label>
          <label className={m4LabelClass}>
            {copy.configuration.numericWidth}
            <Input
              className={m4FieldClass}
              disabled={disabled || working}
              min="1"
              max="18"
              onChange={(event) => setNumericWidth(event.target.value)}
              required
              type="number"
              value={numericWidth}
            />
          </label>
          <label className={m4LabelClass}>
            {copy.configuration.startingValue}
            <Input
              className={m4FieldClass}
              disabled={disabled || working}
              min="0"
              onChange={(event) => setStartingValue(event.target.value)}
              required
              inputMode="numeric"
              value={startingValue}
            />
          </label>
          <label className={m4LabelClass}>
            {copy.configuration.increment}
            <Input
              className={m4FieldClass}
              disabled={disabled || working}
              min="1"
              onChange={(event) => setIncrement(event.target.value)}
              required
              inputMode="numeric"
              value={increment}
            />
          </label>
          <label className={m4LabelClass}>
            {copy.configuration.resetPolicy}
            <NativeSelect
              className={m4FieldClass}
              disabled={disabled || working}
              onChange={(event) => setResetPolicy(event.target.value)}
              value={resetPolicy}
            >
              {Object.entries(copy.configuration.resetPolicies).map(
                ([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ),
              )}
            </NativeSelect>
          </label>
          {resetPolicy === "configured_period" ? (
            <>
              <label className={m4LabelClass}>
                {copy.configuration.periodAnchor}
                <Input
                  className={m4FieldClass}
                  disabled={disabled || working}
                  onChange={(event) => setPeriodAnchor(event.target.value)}
                  required
                  type="date"
                  value={periodAnchor}
                />
              </label>
              <label className={m4LabelClass}>
                {copy.configuration.periodMonths}
                <Input
                  className={m4FieldClass}
                  disabled={disabled || working}
                  min="1"
                  max="120"
                  onChange={(event) => setPeriodMonths(event.target.value)}
                  required
                  type="number"
                  value={periodMonths}
                />
              </label>
            </>
          ) : null}
          <label className={m4LabelClass}>
            {copy.configuration.importPolicy}
            <NativeSelect
              className={m4FieldClass}
              disabled={disabled || working}
              onChange={(event) => setImportPolicy(event.target.value)}
              value={importPolicy}
            >
              {Object.entries(copy.configuration.importPolicies).map(
                ([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ),
              )}
            </NativeSelect>
          </label>
          <label className={m4LabelClass}>
            {copy.configuration.scope}
            <NativeSelect
              className={m4FieldClass}
              disabled={disabled || working}
              onChange={(event) => setScope(event.target.value)}
              value={scope}
            >
              {Object.entries(copy.configuration.scopeTypes).map(
                ([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ),
              )}
            </NativeSelect>
          </label>
          <label className={m4LabelClass}>
            {copy.configuration.timezone}
            <Input
              className={m4FieldClass}
              disabled
              readOnly
              value={timezone}
            />
          </label>
        </div>
        <label className={m4LabelClass}>
          {copy.configuration.reason}
          <Textarea
            className={m4TextAreaClass}
            disabled={disabled || working}
            onChange={(event) => setReason(event.target.value)}
            required
            value={reason}
          />
        </label>
        <Button
          className={`${m4PrimaryButtonClass} justify-self-start`}
          disabled={disabled || working}
          type="submit"
        >
          {working ? (
            <LoaderCircle
              aria-hidden="true"
              className="animate-spin motion-reduce:animate-none"
              size={17}
            />
          ) : (
            <Hash aria-hidden="true" size={17} />
          )}
          {copy.configuration.createNumberingVersion}
        </Button>
        {message ? (
          <M4InlineStatus
            error={message !== copy.common.saved}
            message={message}
          />
        ) : null}
      </form>
    </details>
  );
}

function ApprovalForm({
  copy,
  disabled,
  onCreated,
  runtime,
  targets,
}: {
  readonly copy: M4Messages;
  readonly disabled: boolean;
  readonly onCreated: () => Promise<void>;
  readonly runtime: M4OperatorRuntimeState;
  readonly targets: readonly ArtifactTarget[];
}) {
  const [targetId, setTargetId] = useState(targets[0]?.id ?? "");
  const [approvalType, setApprovalType] = useState("professional_review");
  const [decision, setDecision] = useState("approved");
  const [organization, setOrganization] = useState("");
  const [role, setRole] = useState("");
  const [attachment, setAttachment] = useState("");
  const [expiresAt, setExpiresAt] = useState("");
  const [conditions, setConditions] = useState("{}");
  const [supersedesId, setSupersedesId] = useState("");
  const [reason, setReason] = useState("");
  const [working, setWorking] = useState(false);
  const [message, setMessage] = useState("");
  const selected =
    targets.find((target) => target.id === targetId) ?? targets[0];

  async function submit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    if (!selected) return;
    setWorking(true);
    setMessage("");
    try {
      if (!runtime.previewMode) {
        await requestM4Json({
          body: {
            approvalType,
            artifactId: selected.id,
            artifactType: selected.type,
            attachmentReference: attachment.trim() || null,
            conditions: parseM4JsonObject(conditions),
            decision,
            expectedChecksum: selected.checksum,
            expiresAt: expiresAt ? new Date(expiresAt).toISOString() : null,
            professionalOrganization: organization.trim() || null,
            professionalRole: role.trim() || null,
            reason,
            reviewDueAt: null,
            supersedesApprovalId: decision === "revoked" ? supersedesId : null,
          },
          context: runtime.apiContext,
          idempotencyKey: newM4IdempotencyKey("approval-record"),
          method: "POST",
          path: "/api/v1/approval-records",
        });
      }
      setMessage(copy.common.saved);
      setReason("");
      await onCreated();
    } catch (error) {
      setMessage(
        error instanceof SyntaxError || error instanceof TypeError
          ? copy.documents.fieldInvalidJson
          : safeError(copy, error),
      );
    } finally {
      setWorking(false);
    }
  }

  return (
    <form
      className="grid gap-5 border-b border-[var(--ink)] pb-7"
      onSubmit={(event) => void submit(event)}
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <label className={`${m4LabelClass} sm:col-span-2`}>
          {copy.configuration.artifact}
          <NativeSelect
            className={m4FieldClass}
            disabled={disabled || working || targets.length === 0}
            onChange={(event) => setTargetId(event.target.value)}
            value={selected?.id ?? ""}
          >
            {targets.map((target) => (
              <option key={target.id} value={target.id}>
                {target.label} · v{target.version} ·{" "}
                {target.checksum.slice(0, 10)}
              </option>
            ))}
          </NativeSelect>
        </label>
        <label className={m4LabelClass}>
          {copy.configuration.approvalType}
          <Input
            className={m4FieldClass}
            disabled={disabled || working}
            onChange={(event) => setApprovalType(event.target.value)}
            required
            value={approvalType}
          />
        </label>
        <label className={m4LabelClass}>
          {copy.configuration.approvalDecision}
          <NativeSelect
            className={m4FieldClass}
            disabled={disabled || working}
            onChange={(event) => setDecision(event.target.value)}
            value={decision}
          >
            {Object.entries(copy.configuration.decisions).map(
              ([key, label]) => (
                <option key={key} value={key}>
                  {label}
                </option>
              ),
            )}
          </NativeSelect>
        </label>
        <label className={m4LabelClass}>
          {copy.configuration.approvalOrganization}
          <Input
            className={m4FieldClass}
            disabled={disabled || working}
            onChange={(event) => setOrganization(event.target.value)}
            value={organization}
          />
        </label>
        <label className={m4LabelClass}>
          {copy.configuration.approvalRole}
          <Input
            className={m4FieldClass}
            disabled={disabled || working}
            onChange={(event) => setRole(event.target.value)}
            value={role}
          />
        </label>
        <label className={m4LabelClass}>
          {copy.configuration.approvalAttachment}
          <Input
            className={m4FieldClass}
            disabled={disabled || working}
            onChange={(event) => setAttachment(event.target.value)}
            value={attachment}
          />
        </label>
        <label className={m4LabelClass}>
          {copy.configuration.approvalExpires}
          <Input
            className={m4FieldClass}
            disabled={disabled || working}
            onChange={(event) => setExpiresAt(event.target.value)}
            type="datetime-local"
            value={expiresAt}
          />
        </label>
        {decision === "revoked" ? (
          <label className={`${m4LabelClass} sm:col-span-2`}>
            Superseded approval ID
            <Input
              className={m4FieldClass}
              disabled={disabled || working}
              onChange={(event) => setSupersedesId(event.target.value)}
              required
              value={supersedesId}
            />
          </label>
        ) : null}
        <label className={`${m4LabelClass} sm:col-span-2`}>
          {copy.configuration.approvalConditions}
          <Textarea
            className={m4TextAreaClass}
            disabled={disabled || working}
            onChange={(event) => setConditions(event.target.value)}
            required
            rows={4}
            value={conditions}
          />
        </label>
        <label className={`${m4LabelClass} sm:col-span-2`}>
          {copy.configuration.approvalReason}
          <Textarea
            className={m4TextAreaClass}
            disabled={disabled || working}
            onChange={(event) => setReason(event.target.value)}
            required
            value={reason}
          />
        </label>
      </div>
      <Button
        className={`${m4PrimaryButtonClass} justify-self-start`}
        disabled={disabled || working || !selected}
        type="submit"
      >
        {working ? (
          <LoaderCircle
            aria-hidden="true"
            className="animate-spin motion-reduce:animate-none"
            size={17}
          />
        ) : (
          <BadgeCheck aria-hidden="true" size={17} />
        )}
        {copy.configuration.createApproval}
      </Button>
      {message ? (
        <M4InlineStatus
          error={message !== copy.common.saved}
          message={message}
        />
      ) : null}
    </form>
  );
}

function ConfigurationSurface({
  copy,
  locale,
  runtime,
}: {
  readonly copy: M4Messages;
  readonly locale: Locale;
  readonly runtime: M4OperatorRuntimeState;
}) {
  const [numbering, setNumbering] = useState<readonly M4NumberingDefinition[]>(
    [],
  );
  const [calculations, setCalculations] = useState<
    readonly M4CalculationDefinition[]
  >([]);
  const [taxPacks, setTaxPacks] = useState<readonly M4TaxPack[]>([]);
  const [approvals, setApprovals] = useState<readonly M4ApprovalRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState("");
  const [calculationDefinition, setCalculationDefinition] = useState(
    '{"checksum":"' +
      checksumB +
      '","engineVersion":"1.0.0","expressionAst":{},"fixtures":[],"inputSchema":{},"outputSchema":{},"resourceLimits":{},"roundingPolicy":{}}',
  );
  const [calculationInputs, setCalculationInputs] = useState("{}");
  const [calculationVersionId, setCalculationVersionId] = useState("");
  const [runtimeDealId, setRuntimeDealId] = useState("");
  const [taxContext, setTaxContext] = useState("retail_sale");
  const [taxJurisdiction, setTaxJurisdiction] = useState("CA-QC");
  const [taxCurrency, setTaxCurrency] = useState("CAD");
  const [taxDate, setTaxDate] = useState(new Date().toISOString().slice(0, 10));
  const [taxInputs, setTaxInputs] = useState(
    '{"vehicle_price_minor":"100000","taxable_fees_minor":"0","non_taxable_fees_minor":"0","eligible_trade_in_credit_minor":"0"}',
  );
  const [previewOutput, setPreviewOutput] = useState<unknown>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const results = runtime.previewMode
        ? ([
            previewNumbering,
            previewCalculations,
            previewTaxes,
            previewApprovals,
          ] as const)
        : await Promise.all([
            requestM4Json<readonly M4NumberingDefinition[]>({
              context: runtime.apiContext,
              path: "/api/v1/numbering-definitions",
            }),
            requestM4Json<readonly M4CalculationDefinition[]>({
              context: runtime.apiContext,
              path: "/api/v1/calculation-definitions",
            }),
            requestM4Json<readonly M4TaxPack[]>({
              context: runtime.apiContext,
              path: "/api/v1/tax-packs",
            }),
            requestM4Json<readonly M4ApprovalRecord[]>({
              context: runtime.apiContext,
              path: "/api/v1/approval-records?current_only=true&limit=100",
            }),
          ]);
      setNumbering(results[0]);
      setCalculations(results[1]);
      setTaxPacks(results[2]);
      setApprovals(results[3]);
      setCalculationVersionId(
        (current) =>
          current ||
          results[1][0]?.active_version_id ||
          results[1][0]?.versions[0]?.id ||
          "",
      );
    } catch (loadError) {
      setError(safeError(copy, loadError));
    } finally {
      setLoading(false);
    }
  }, [copy, runtime.apiContext, runtime.previewMode]);

  useEffect(() => {
    let active = true;
    queueMicrotask(() => {
      if (active) void load();
    });
    return () => {
      active = false;
    };
  }, [load]);

  const targets = useMemo<readonly ArtifactTarget[]>(
    () => [
      ...numbering.flatMap((definition) =>
        definition.versions.map((version) => ({
          checksum: version.checksum,
          id: version.id,
          key: definition.key,
          label: `${copy.configuration.artifactTypes.numbering_definition}: ${localizedM4Label(definition.labels, locale, definition.key)}`,
          status: version.status,
          type: "numbering_definition" as const,
          version: version.version,
        })),
      ),
      ...calculations.flatMap((definition) =>
        definition.versions.map((version) => ({
          checksum: version.checksum,
          id: version.id,
          key: definition.key,
          label: `${copy.configuration.artifactTypes.calculation}: ${localizedM4Label(definition.labels, locale, definition.key)}`,
          status: version.status,
          type: "calculation" as const,
          version: version.version,
        })),
      ),
      ...taxPacks.flatMap((pack) =>
        pack.versions.map((version) => ({
          checksum: version.checksum,
          id: version.id,
          key: pack.key,
          label: `${copy.configuration.artifactTypes.tax_pack}: ${localizedM4Label(pack.labels, locale, pack.key)}`,
          status: version.status,
          type: "tax_pack" as const,
          version: version.version,
        })),
      ),
    ],
    [
      calculations,
      copy.configuration.artifactTypes,
      locale,
      numbering,
      taxPacks,
    ],
  );

  async function lifecycle(
    target: ArtifactTarget,
    action: "activate" | "approve",
    reason: string,
  ): Promise<void> {
    setWorking(`${action}:${target.id}`);
    setError(null);
    setNotice("");
    try {
      if (!runtime.previewMode) {
        const base =
          target.type === "numbering_definition"
            ? "numbering-versions"
            : target.type === "calculation"
              ? "calculation-versions"
              : "tax-pack-versions";
        await requestM4Json({
          body: {
            expectedChecksum: target.checksum,
            expectedVersion: target.version,
            reason,
          },
          context: runtime.apiContext,
          idempotencyKey: newM4IdempotencyKey(`${target.type}-${action}`),
          method: "POST",
          path: `/api/v1/${base}/${target.id}/${action}`,
        });
      }
      setNotice(copy.common.saved);
      await load();
    } catch (actionError) {
      setError(safeError(copy, actionError));
    } finally {
      setWorking(null);
    }
  }

  async function runCalculation(kind: "preview" | "validate"): Promise<void> {
    setWorking(`calculation-${kind}`);
    setError(null);
    setPreviewOutput(null);
    try {
      const result = runtime.previewMode
        ? kind === "validate"
          ? {
              checksum_matches: true,
              errors: [],
              fixture_count: 2,
              valid: true,
              warnings: [],
            }
          : {
              calculation_version_id: calculationVersionId,
              checksum: checksumB,
              components: [],
              engine_version: "1.0.0",
              output: { total_minor: "100000" },
              rounding: { mode: "half_even" },
            }
        : await requestM4Json({
            body:
              kind === "validate"
                ? { definition: parseM4JsonObject(calculationDefinition) }
                : {
                    calculationVersionId,
                    dealId: runtimeDealId.trim() || null,
                    inputs: parseM4JsonObject(calculationInputs),
                  },
            context: runtime.apiContext,
            idempotencyKey: newM4IdempotencyKey(`calculation-${kind}`),
            method: "POST",
            path:
              kind === "validate"
                ? "/api/v1/calculations/validate"
                : "/api/v1/calculations/run-preview",
          });
      setPreviewOutput(result);
    } catch (previewError) {
      setError(
        previewError instanceof SyntaxError || previewError instanceof TypeError
          ? copy.documents.fieldInvalidJson
          : safeError(copy, previewError),
      );
    } finally {
      setWorking(null);
    }
  }

  async function runTaxPreview(): Promise<void> {
    setWorking("tax-preview");
    setError(null);
    setPreviewOutput(null);
    try {
      const result = runtime.previewMode
        ? {
            assignment_id: "41000000-0000-4000-8000-000000000409",
            checksum: checksumC,
            components: [],
            currency_code: taxCurrency,
            engine_version: "1.0.0",
            output: { tax_minor: "14975" },
            tax_pack_version_id: previewTaxes[0]!.versions[0]!.id,
          }
        : await requestM4Json({
            body: {
              contextKey: taxContext,
              currencyCode: taxCurrency,
              dealId: runtimeDealId.trim() || null,
              inputs: parseM4JsonObject(taxInputs),
              jurisdictionCode: taxJurisdiction,
              override: null,
              overrideReason: null,
              transactionDate: taxDate,
            },
            context: runtime.apiContext,
            idempotencyKey: newM4IdempotencyKey("tax-preview"),
            method: "POST",
            path: "/api/v1/tax/calculate-preview",
          });
      setPreviewOutput(result);
    } catch (previewError) {
      setError(
        previewError instanceof SyntaxError || previewError instanceof TypeError
          ? copy.documents.fieldInvalidJson
          : safeError(copy, previewError),
      );
    } finally {
      setWorking(null);
    }
  }

  return (
    <div className="mx-auto max-w-[90rem] px-4 sm:px-6 lg:px-8">
      <div className="flex flex-wrap items-center justify-between gap-4 border-b border-[var(--line)] py-5">
        <p className="m-0 max-w-2xl text-sm text-muted-foreground">
          {copy.configuration.activationHint}
        </p>
        <Button
          className={m4SecondaryButtonClass}
          disabled={loading}
          onClick={() => void load()}
          type="button"
        >
          <RefreshCcw
            aria-hidden="true"
            className={loading ? "animate-spin motion-reduce:animate-none" : ""}
            size={17}
          />
          {copy.configuration.refresh}
        </Button>
      </div>
      {error ? (
        <div
          className="mt-5 flex gap-3 rounded-[var(--radius-panel)] border border-destructive/40 bg-destructive/5 p-4"
          role="alert"
        >
          <AlertTriangle aria-hidden="true" size={18} />
          <p className="m-0 text-sm font-semibold">{error}</p>
        </div>
      ) : null}
      {notice ? <M4InlineStatus message={notice} /> : null}
      {loading ? (
        <div
          className="flex min-h-48 items-center justify-center gap-3"
          role="status"
        >
          <LoaderCircle
            aria-hidden="true"
            className="animate-spin motion-reduce:animate-none"
            size={20}
          />
          {copy.common.loading}
        </div>
      ) : null}

      {!loading ? (
        <>
          <DefinitionSection
            description={copy.configuration.numberingHint}
            heading={copy.configuration.numberingHeading}
            icon={<Hash aria-hidden="true" size={24} strokeWidth={1.6} />}
            id="m4-numbering-heading"
          >
            {numbering.length === 0 ? (
              <p className="m-0 text-sm text-muted-foreground">
                {copy.configuration.empty}
              </p>
            ) : (
              numbering.map((definition) => (
                <article
                  className="border-t border-[var(--ink)]"
                  key={definition.id}
                >
                  <header className="grid gap-2 py-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center">
                    <div>
                      <h3 className="m-0 text-lg">
                        {localizedM4Label(
                          definition.labels,
                          locale,
                          definition.key,
                        )}
                      </h3>
                      <p className="mt-1 mb-0 font-mono text-xs text-muted-foreground">
                        {definition.key}
                      </p>
                    </div>
                    <span className="font-mono text-xs">
                      {definition.active_version_id
                        ? `active · ${definition.active_version_id.slice(0, 8)}`
                        : "—"}
                    </span>
                  </header>
                  {definition.versions.map((version) => {
                    const target = targets.find(
                      (candidate) => candidate.id === version.id,
                    )!;
                    return (
                      <VersionRow
                        actionLabel={copy.configuration.activate}
                        canAction={
                          runtime.canWrite &&
                          (version.status === "approved" ||
                            version.status === "test_passed")
                        }
                        checksum={version.checksum}
                        copy={copy}
                        {...(version.approval_record_id
                          ? {
                              detail: `${copy.configuration.latestApproval}: ${version.approval_record_id.slice(0, 8)}`,
                            }
                          : {})}
                        key={version.id}
                        onAction={(reason) =>
                          lifecycle(target, "activate", reason)
                        }
                        semanticVersion={version.semantic_version}
                        status={version.status}
                        version={version.version}
                        working={working === `activate:${version.id}`}
                      />
                    );
                  })}
                </article>
              ))
            )}
            <NumberingVersionForm
              copy={copy}
              definition={numbering[0]}
              disabled={!runtime.canWrite}
              onCreated={load}
              runtime={runtime}
            />
          </DefinitionSection>

          <DefinitionSection
            description={copy.configuration.activationHint}
            heading={copy.configuration.calculationHeading}
            icon={<Calculator aria-hidden="true" size={24} strokeWidth={1.6} />}
            id="m4-calculations-heading"
          >
            {calculations.length === 0 ? (
              <p className="m-0 text-sm text-muted-foreground">
                {copy.configuration.empty}
              </p>
            ) : (
              calculations.map((definition) => (
                <article
                  className="border-t border-[var(--ink)]"
                  key={definition.id}
                >
                  <header className="py-4">
                    <h3 className="m-0 text-lg">
                      {localizedM4Label(
                        definition.labels,
                        locale,
                        definition.key,
                      )}
                    </h3>
                    <p className="mt-1 mb-0 font-mono text-xs text-muted-foreground">
                      {definition.key}
                    </p>
                  </header>
                  {definition.versions.map((version) => {
                    const target = targets.find(
                      (candidate) => candidate.id === version.id,
                    )!;
                    const action =
                      version.status === "test_passed" ? "approve" : "activate";
                    return (
                      <VersionRow
                        actionLabel={
                          action === "approve"
                            ? copy.configuration.approve
                            : copy.configuration.activate
                        }
                        canAction={
                          runtime.canWrite &&
                          (version.status === "test_passed" ||
                            version.status === "approved")
                        }
                        checksum={version.checksum}
                        copy={copy}
                        detail={`engine ${version.engine_version}`}
                        key={version.id}
                        onAction={(reason) => lifecycle(target, action, reason)}
                        semanticVersion={version.semantic_version}
                        status={version.status}
                        version={version.version}
                        working={working === `${action}:${version.id}`}
                      />
                    );
                  })}
                </article>
              ))
            )}
            <details className="border-b border-[var(--ink)] py-4">
              <summary className="min-h-11 cursor-pointer font-bold">
                {copy.configuration.calculationValidate}
              </summary>
              <div className="mt-5 grid gap-5">
                <label className={m4LabelClass}>
                  {copy.configuration.dealId}
                  <Input
                    aria-describedby="m4-deal-input-hint"
                    className={m4FieldClass}
                    inputMode="text"
                    onChange={(event) => setRuntimeDealId(event.target.value)}
                    placeholder="00000000-0000-4000-8000-000000000000"
                    value={runtimeDealId}
                  />
                  <span
                    className="font-normal text-xs text-muted-foreground"
                    id="m4-deal-input-hint"
                  >
                    {copy.configuration.dealInputHint}
                  </span>
                </label>
                <label className={m4LabelClass}>
                  {copy.configuration.calculationDefinition}
                  <Textarea
                    className={m4TextAreaClass}
                    onChange={(event) =>
                      setCalculationDefinition(event.target.value)
                    }
                    rows={10}
                    value={calculationDefinition}
                  />
                </label>
                <Button
                  className={`${m4SecondaryButtonClass} justify-self-start`}
                  disabled={!runtime.canWrite || working !== null}
                  onClick={() => void runCalculation("validate")}
                  type="button"
                >
                  <FlaskConical aria-hidden="true" size={17} />
                  {copy.configuration.calculationValidate}
                </Button>
                <div className="grid gap-4 sm:grid-cols-2">
                  <label className={m4LabelClass}>
                    {copy.configuration.artifact}
                    <NativeSelect
                      className={m4FieldClass}
                      onChange={(event) =>
                        setCalculationVersionId(event.target.value)
                      }
                      value={calculationVersionId}
                    >
                      {calculations.flatMap((definition) =>
                        definition.versions.map((version) => (
                          <option key={version.id} value={version.id}>
                            {localizedM4Label(
                              definition.labels,
                              locale,
                              definition.key,
                            )}{" "}
                            · {version.semantic_version}
                          </option>
                        )),
                      )}
                    </NativeSelect>
                  </label>
                  <label className={m4LabelClass}>
                    {copy.configuration.calculationPreviewInputs}
                    <Textarea
                      className={m4TextAreaClass}
                      onChange={(event) =>
                        setCalculationInputs(event.target.value)
                      }
                      rows={4}
                      value={calculationInputs}
                    />
                  </label>
                </div>
                <Button
                  className={`${m4PrimaryButtonClass} justify-self-start`}
                  disabled={
                    !runtime.canWrite ||
                    working !== null ||
                    !calculationVersionId
                  }
                  onClick={() => void runCalculation("preview")}
                  type="button"
                >
                  <Calculator aria-hidden="true" size={17} />
                  {copy.configuration.calculationPreview}
                </Button>
              </div>
            </details>
          </DefinitionSection>

          <DefinitionSection
            description={copy.configuration.activationHint}
            heading={copy.configuration.taxHeading}
            icon={<Scale aria-hidden="true" size={24} strokeWidth={1.6} />}
            id="m4-tax-heading"
          >
            {taxPacks.length === 0 ? (
              <p className="m-0 text-sm text-muted-foreground">
                {copy.configuration.empty}
              </p>
            ) : (
              taxPacks.map((pack) => (
                <article className="border-t border-[var(--ink)]" key={pack.id}>
                  <header className="py-4">
                    <h3 className="m-0 text-lg">
                      {localizedM4Label(pack.labels, locale, pack.key)}
                    </h3>
                    <p className="mt-1 mb-0 font-mono text-xs text-muted-foreground">
                      {pack.key} · {pack.source_kind}
                    </p>
                  </header>
                  {pack.versions.map((version) => {
                    const target = targets.find(
                      (candidate) => candidate.id === version.id,
                    )!;
                    return (
                      <VersionRow
                        actionLabel={copy.configuration.activate}
                        canAction={
                          runtime.canWrite &&
                          (version.status === "approved" ||
                            version.status === "test_passed")
                        }
                        checksum={version.checksum}
                        copy={copy}
                        detail={`${version.jurisdiction_code} · ${version.contexts.join(", ")} · ${version.effective_from}—${version.effective_to ?? "∞"}`}
                        key={version.id}
                        onAction={(reason) =>
                          lifecycle(target, "activate", reason)
                        }
                        semanticVersion={version.semantic_version}
                        status={version.status}
                        version={version.version}
                        working={working === `activate:${version.id}`}
                      />
                    );
                  })}
                </article>
              ))
            )}
            <details className="border-b border-[var(--ink)] py-4">
              <summary className="min-h-11 cursor-pointer font-bold">
                {copy.configuration.taxPreview}
              </summary>
              <div className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <label
                  className={`${m4LabelClass} sm:col-span-2 lg:col-span-4`}
                >
                  {copy.configuration.dealId}
                  <Input
                    aria-describedby="m4-tax-deal-input-hint"
                    className={m4FieldClass}
                    inputMode="text"
                    onChange={(event) => setRuntimeDealId(event.target.value)}
                    placeholder="00000000-0000-4000-8000-000000000000"
                    value={runtimeDealId}
                  />
                  <span
                    className="font-normal text-xs text-muted-foreground"
                    id="m4-tax-deal-input-hint"
                  >
                    {copy.configuration.dealInputHint}
                  </span>
                </label>
                <label className={m4LabelClass}>
                  {copy.configuration.taxContext}
                  <Input
                    className={m4FieldClass}
                    onChange={(event) => setTaxContext(event.target.value)}
                    value={taxContext}
                  />
                </label>
                <label className={m4LabelClass}>
                  {copy.configuration.jurisdiction}
                  <Input
                    className={m4FieldClass}
                    onChange={(event) => setTaxJurisdiction(event.target.value)}
                    value={taxJurisdiction}
                  />
                </label>
                <label className={m4LabelClass}>
                  {copy.configuration.taxCurrency}
                  <Input
                    className={m4FieldClass}
                    maxLength={3}
                    onChange={(event) =>
                      setTaxCurrency(event.target.value.toUpperCase())
                    }
                    value={taxCurrency}
                  />
                </label>
                <label className={m4LabelClass}>
                  {copy.configuration.taxDate}
                  <Input
                    className={m4FieldClass}
                    onChange={(event) => setTaxDate(event.target.value)}
                    type="date"
                    value={taxDate}
                  />
                </label>
                <label
                  className={`${m4LabelClass} sm:col-span-2 lg:col-span-4`}
                >
                  {copy.configuration.taxInputs}
                  <Textarea
                    className={m4TextAreaClass}
                    onChange={(event) => setTaxInputs(event.target.value)}
                    rows={5}
                    value={taxInputs}
                  />
                </label>
                <Button
                  className={`${m4PrimaryButtonClass} justify-self-start sm:col-span-2`}
                  disabled={!runtime.canWrite || working !== null}
                  onClick={() => void runTaxPreview()}
                  type="button"
                >
                  <Scale aria-hidden="true" size={17} />
                  {copy.configuration.taxPreview}
                </Button>
              </div>
            </details>
          </DefinitionSection>

          {previewOutput ? (
            <section
              className={m4SectionClass}
              aria-labelledby="m4-preview-output-heading"
            >
              <h2 className="text-2xl" id="m4-preview-output-heading">
                {copy.configuration.previewOutput}
              </h2>
              <pre className="max-h-96 overflow-auto bg-[var(--ink)] p-4 text-xs leading-5 whitespace-pre-wrap text-[var(--paper)]">
                {JSON.stringify(previewOutput, null, 2)}
              </pre>
            </section>
          ) : null}

          <DefinitionSection
            description={copy.configuration.stepUpHint}
            heading={copy.configuration.approvalHeading}
            icon={<BadgeCheck aria-hidden="true" size={24} strokeWidth={1.6} />}
            id="m4-approvals-heading"
          >
            <ApprovalForm
              copy={copy}
              disabled={!runtime.canWrite}
              onCreated={load}
              runtime={runtime}
              targets={targets}
            />
            {approvals.length === 0 ? (
              <p className="py-5 text-sm text-muted-foreground">
                {copy.configuration.empty}
              </p>
            ) : (
              <ol className="m-0 list-none border-t border-[var(--ink)] p-0">
                {approvals.map((approval) => (
                  <li
                    className="grid gap-3 border-b border-[var(--line)] py-4 sm:grid-cols-[minmax(0,1fr)_auto]"
                    key={approval.id}
                  >
                    <div className="min-w-0">
                      <p className="m-0 break-words text-sm font-bold">
                        {approval.artifact_key} · v{approval.artifact_version}
                      </p>
                      <p className="mt-1 mb-0 text-xs text-muted-foreground">
                        {copy.configuration.artifactTypes[
                          approval.artifact_type
                        ] ?? approval.artifact_type}{" "}
                        · {approval.professional_role ?? approval.approval_type}{" "}
                        · {formatDate(approval.decided_at, locale)}
                      </p>
                      <code className="mt-2 block truncate text-[0.68rem] text-muted-foreground">
                        {approval.artifact_checksum}
                      </code>
                    </div>
                    <M4StatusPill
                      label={
                        copy.configuration.decisions[approval.decision] ??
                        approval.decision
                      }
                      status={approval.decision}
                    />
                  </li>
                ))}
              </ol>
            )}
          </DefinitionSection>
        </>
      ) : null}
    </div>
  );
}

export function M4ConfigurationWorkbench({
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
        previewTaxes.filter((pack) => pack.active_versions.length === 0).length
      }
      copy={copy}
      current="configuration"
      eyebrow={copy.configuration.status}
      locale={locale}
      previewMode={previewMode}
      summary={copy.configuration.summary}
      title={copy.configuration.heading}
    >
      {(runtime) => (
        <ConfigurationSurface
          copy={copy}
          key={runtime.selectedWorkspaceId}
          locale={locale}
          runtime={runtime}
        />
      )}
    </M4OperatorRuntime>
  );
}
