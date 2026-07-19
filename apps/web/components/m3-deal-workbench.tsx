/* Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4
 * Hallmark · genre: modern-minimal · macrostructure: Workbench
 * tone: utilitarian-austere · palette: inherited Vynlo · enrichment: none
 */
"use client";

import { Button } from "@vynlo/ui-web";
import { Checkbox } from "@vynlo/ui-web/components/checkbox";
import { Input } from "@vynlo/ui-web/components/input";
import { NativeSelect } from "@vynlo/ui-web/components/native-select";
import { Textarea } from "@vynlo/ui-web/components/textarea";
import {
  ArrowLeft,
  ArrowRight,
  BadgeDollarSign,
  Check,
  CircleAlert,
  LoaderCircle,
  Plus,
  ReceiptText,
  RefreshCcw,
} from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  type FormEvent,
  type ReactNode,
  useCallback,
  useEffect,
  useState,
} from "react";

import type { Locale } from "../i18n/messages";
import { m3Messages, type M3Messages } from "../i18n/m3-messages";
import { M3ApiError, requestM3Json } from "../lib/m3-api-client";
import {
  type LocalizedDealOption,
  localizedDealOptionLabel,
} from "../lib/m3-localized-options";
import { formatM3MinorAmount } from "../lib/m3-money";
import {
  paymentCorrectableMinor,
  previewPaymentCorrectionRemainingMinor,
} from "../lib/m3-payment-preview";
import {
  M3InlineStatus,
  M3OperatorRuntime,
  type M3OperatorRuntimeState,
  m3FieldClass,
  m3LinkButtonClass,
  m3PrimaryButtonClass,
  m3SecondaryButtonClass,
  m3TextAreaClass,
} from "./m3-operator-runtime";

export type M3DealView =
  "deal-detail" | "deal-new" | "deals" | "finance" | "payments" | "trade-ins";

interface M3DealWorkbenchProps {
  readonly dealId?: string;
  readonly locale: Locale;
  readonly previewMode: boolean;
  readonly view: M3DealView;
}

interface DealListRow {
  readonly activeInventoryCount: number;
  readonly activeLineItemCount: number;
  readonly activeParticipantCount: number;
  readonly aggregateVersion: number;
  readonly canonicalStatus: string;
  readonly currencyCode: string;
  readonly dealId: string;
  readonly dealTypeKey: string;
  readonly dealTypeLabels: Readonly<{ en: string; fr: string }>;
  readonly notes: string | null;
  readonly stateKey: string;
  readonly updatedAt: string;
}

interface DealDetailRow {
  readonly aggregateVersion: number;
  readonly availableTransitions: readonly {
    readonly labels: Readonly<Record<Locale, string>>;
    readonly reasonRequired: boolean;
    readonly toStateKey: string;
    readonly transitionKey: string;
  }[];
  readonly canonicalStatus: string;
  readonly currencyCode: string;
  readonly dealId: string;
  readonly dealTypeKey: string;
  readonly dealTypeLabels: Readonly<{ en: string; fr: string }>;
  readonly inventoryRoleOptions: readonly LocalizedDealOption[];
  readonly notes: string | null;
  readonly oneTimeEventTypeOptions: readonly LocalizedDealOption[];
  readonly participantRoleOptions: readonly LocalizedDealOption[];
  readonly stateKey: string;
  readonly updatedAt: string;
}

interface M3CommandEvidence {
  readonly aggregateVersion: number;
  readonly auditEventId: string;
  readonly outboxEventId: string;
  readonly replayed: boolean;
}

export async function runM3DealMutation<TResult>(input: {
  readonly execute: () => Promise<TResult>;
  readonly previewMode: boolean;
  readonly previewResult: TResult;
  readonly refresh: (result: TResult) => Promise<void>;
}): Promise<TResult> {
  if (input.previewMode) return input.previewResult;
  const result = await input.execute();
  await input.refresh(result);
  return result;
}

interface TradeInRow {
  readonly allowanceMinor: string;
  readonly conditionKey: string | null;
  readonly currencyCode: string;
  readonly dealId: string;
  readonly enteredVehicleFacts: Readonly<{
    make?: string;
    model?: string;
    vin?: string;
    year?: string;
  }>;
  readonly lenderPartyId: string | null;
  readonly lienAmountMinor: string;
  readonly odometerUnit: "km" | "mi" | null;
  readonly odometerValue: number | null;
  readonly ownerPartyId: string;
  readonly payoffAmountMinor: string;
  readonly resultingInventoryUnitId: string | null;
  readonly status: string;
  readonly taxEligibilityInputs: Readonly<Record<string, unknown>>;
  readonly tradeInId: string;
  readonly vehicleId: string | null;
  readonly version: number;
}

interface FinanceConditionRow {
  readonly conditionId: string;
  readonly conditionKey: string;
  readonly createdAt: string;
  readonly description: string;
  readonly dueAt: string | null;
  readonly logicalConditionId: string;
  readonly replacesConditionId: string | null;
  readonly required: boolean;
  readonly satisfiedAt: string | null;
  readonly status: "active";
  readonly supportingFileId: string | null;
  readonly version: number;
}

interface FinanceRow {
  readonly applicantPartyId: string;
  readonly approvalExpiresAt: string | null;
  readonly approvedAmountMinor: string | null;
  readonly conditions: readonly FinanceConditionRow[];
  readonly customerAcceptedAt: string | null;
  readonly currencyCode: string;
  readonly dealId: string;
  readonly externalReference: string | null;
  readonly financeApplicationId: string;
  readonly fundedAt: string | null;
  readonly fundingReference: string | null;
  readonly lenderPartyId: string;
  readonly lenderReportedAnnualRate: string | null;
  readonly lenderReportedTermMonths: number | null;
  readonly notes: string | null;
  readonly requestedAmountMinor: string;
  readonly status: string;
  readonly statusReason: string | null;
  readonly submittedAt: string | null;
  readonly updatedAt: string;
  readonly version: number;
}

interface PaymentRow {
  readonly amountMinor: string;
  readonly correctsTransactionId: string | null;
  readonly correctionReason: string | null;
  readonly createdAt: string;
  readonly currencyCode: string;
  readonly lastUpdatedByUserId: string;
  readonly methodKey: string | null;
  readonly notes: string | null;
  readonly occurredAt: string;
  readonly paymentTransactionId: string;
  readonly proofFileId: string | null;
  readonly recordedByUserId: string;
  readonly reference: string | null;
  readonly settledAt: string | null;
  readonly status: string;
  readonly transactionType: string;
  readonly updatedAt: string;
  readonly version: number;
}

interface ParticipantRow {
  readonly isPrimary: boolean;
  readonly participantId: string;
  readonly partyDisplayName: string;
  readonly partyId: string;
  readonly roleKey: string;
  readonly status: "active" | "released";
  readonly version: number;
}

interface InventoryLinkRow {
  readonly amountMinor: string | null;
  readonly currencyCode: string | null;
  readonly inventoryLinkId: string;
  readonly inventoryStatus: string;
  readonly inventoryUnitId: string;
  readonly roleKey: string;
  readonly status: "active" | "released";
  readonly stockNumber: string;
  readonly version: number;
}

interface LineItemRow {
  readonly currencyCode: string;
  readonly itemType:
    "accessory" | "discount" | "fee" | "other" | "service" | "vehicle";
  readonly key: string;
  readonly label: string;
  readonly lineItemId: string;
  readonly paymentTimingKey: string | null;
  readonly quantity: string;
  readonly sortOrder: number;
  readonly sourceKey: string | null;
  readonly sourceReference: string | null;
  readonly status: string;
  readonly taxClassificationKey: string | null;
  readonly unitAmountMinor: string;
  readonly version: number;
}

type M3MutationMethod = "DELETE" | "PATCH" | "POST";

const previewIds = Object.freeze({
  applicant: "10000000-0000-4000-8000-000000000501",
  dealA: "10000000-0000-4000-8000-000000000801",
  dealB: "10000000-0000-4000-8000-000000000802",
  finance: "10000000-0000-4000-8000-000000000821",
  inventory: "10000000-0000-4000-8000-000000000101",
  inventoryLink: "10000000-0000-4000-8000-000000000812",
  lineItem: "10000000-0000-4000-8000-000000000813",
  legalEntity: "10000000-0000-4000-8000-000000000711",
  lender: "10000000-0000-4000-8000-000000000531",
  location: "10000000-0000-4000-8000-000000000701",
  membership: "10000000-0000-4000-8000-000000000601",
  payment: "10000000-0000-4000-8000-000000000831",
  participant: "10000000-0000-4000-8000-000000000814",
  tradeIn: "10000000-0000-4000-8000-000000000811",
});

const previewParticipantRoleOptions = Object.freeze([
  Object.freeze({
    key: "buyer",
    labels: Object.freeze({ en: "Buyer", fr: "Acheteur" }),
  }),
  Object.freeze({
    key: "seller",
    labels: Object.freeze({ en: "Seller", fr: "Vendeur" }),
  }),
  Object.freeze({
    key: "lender",
    labels: Object.freeze({ en: "Lender", fr: "Prêteur" }),
  }),
  Object.freeze({
    key: "trade_in_owner",
    labels: Object.freeze({
      en: "Trade-in owner",
      fr: "Propriétaire du véhicule d’échange",
    }),
  }),
  Object.freeze({
    key: "authorized_representative",
    labels: Object.freeze({
      en: "Authorized representative",
      fr: "Représentant autorisé",
    }),
  }),
] satisfies readonly LocalizedDealOption[]);

const previewCashParticipantRoleOptions = Object.freeze(
  previewParticipantRoleOptions.filter((option) => option.key !== "lender"),
);

const previewInventoryRoleOptions = Object.freeze([
  Object.freeze({
    key: "sold",
    labels: Object.freeze({ en: "Sale vehicle", fr: "Véhicule vendu" }),
  }),
  Object.freeze({
    key: "trade_in",
    labels: Object.freeze({ en: "Trade-in vehicle", fr: "Véhicule d’échange" }),
  }),
] satisfies readonly LocalizedDealOption[]);

const previewOneTimeEventTypeOptions = Object.freeze([
  Object.freeze({
    key: "deposit",
    labels: Object.freeze({ en: "Deposit", fr: "Dépôt" }),
  }),
  Object.freeze({
    key: "receipt",
    labels: Object.freeze({ en: "Receipt", fr: "Encaissement" }),
  }),
  Object.freeze({
    key: "balance_received",
    labels: Object.freeze({ en: "Balance received", fr: "Solde reçu" }),
  }),
  Object.freeze({
    key: "trade_in_credit",
    labels: Object.freeze({ en: "Trade-in credit", fr: "Crédit d’échange" }),
  }),
  Object.freeze({
    key: "lender_proceeds",
    labels: Object.freeze({ en: "Lender proceeds", fr: "Fonds du prêteur" }),
  }),
] satisfies readonly LocalizedDealOption[]);

const previewCashOneTimeEventTypeOptions = Object.freeze(
  previewOneTimeEventTypeOptions.filter(
    (option) => option.key !== "lender_proceeds",
  ),
);

export const M3_PREVIEW_DEALS: readonly (DealListRow & DealDetailRow)[] =
  Object.freeze([
    Object.freeze({
      activeInventoryCount: 1,
      activeLineItemCount: 3,
      activeParticipantCount: 2,
      aggregateVersion: 7,
      availableTransitions: Object.freeze([
        Object.freeze({
          labels: Object.freeze({ en: "Approved", fr: "Approuvé" }),
          reasonRequired: false,
          toStateKey: "approved",
          transitionKey: "awaiting_lender__approved",
        }),
        Object.freeze({
          labels: Object.freeze({ en: "Cancelled", fr: "Annulé" }),
          reasonRequired: true,
          toStateKey: "cancelled",
          transitionKey: "awaiting_lender__cancelled",
        }),
      ]),
      canonicalStatus: "active",
      currencyCode: "CAD",
      dealId: previewIds.dealA,
      dealTypeKey: "retail.third_party_financed",
      dealTypeLabels: Object.freeze({
        en: "Retail finance",
        fr: "Financement au détail",
      }),
      inventoryRoleOptions: previewInventoryRoleOptions,
      notes: "Delivery preference recorded with customer.",
      oneTimeEventTypeOptions: previewOneTimeEventTypeOptions,
      participantRoleOptions: previewParticipantRoleOptions,
      stateKey: "awaiting_lender",
      updatedAt: "2026-07-16T13:20:00.000Z",
    }),
    Object.freeze({
      activeInventoryCount: 1,
      activeLineItemCount: 2,
      activeParticipantCount: 1,
      aggregateVersion: 4,
      availableTransitions: Object.freeze([
        Object.freeze({
          labels: Object.freeze({
            en: "Awaiting customer",
            fr: "En attente du client",
          }),
          reasonRequired: false,
          toStateKey: "awaiting_customer",
          transitionKey: "preparing__awaiting_customer",
        }),
        Object.freeze({
          labels: Object.freeze({
            en: "Awaiting lender",
            fr: "En attente du prêteur",
          }),
          reasonRequired: false,
          toStateKey: "awaiting_lender",
          transitionKey: "preparing__awaiting_lender",
        }),
        Object.freeze({
          labels: Object.freeze({ en: "Cancelled", fr: "Annulé" }),
          reasonRequired: true,
          toStateKey: "cancelled",
          transitionKey: "preparing__cancelled",
        }),
      ]),
      canonicalStatus: "active",
      currencyCode: "CAD",
      dealId: previewIds.dealB,
      dealTypeKey: "retail.cash",
      dealTypeLabels: Object.freeze({
        en: "Retail cash",
        fr: "Vente comptant",
      }),
      inventoryRoleOptions: previewInventoryRoleOptions,
      notes: null,
      oneTimeEventTypeOptions: previewCashOneTimeEventTypeOptions,
      participantRoleOptions: previewCashParticipantRoleOptions,
      stateKey: "preparing",
      updatedAt: "2026-07-16T11:05:00.000Z",
    }),
  ]);

const previewTradeIns: readonly TradeInRow[] = Object.freeze([
  Object.freeze({
    allowanceMinor: "1250000",
    conditionKey: null,
    currencyCode: "CAD",
    dealId: previewIds.dealA,
    enteredVehicleFacts: Object.freeze({
      make: "Toyota",
      model: "Corolla",
      vin: "2T1BURHE0KC000111",
      year: "2019",
    }),
    lenderPartyId: null,
    lienAmountMinor: "420000",
    odometerUnit: null,
    odometerValue: null,
    ownerPartyId: previewIds.applicant,
    payoffAmountMinor: "420000",
    resultingInventoryUnitId: null,
    status: "active",
    taxEligibilityInputs: Object.freeze({}),
    tradeInId: previewIds.tradeIn,
    vehicleId: null,
    version: 1,
  }),
]);

const previewFinance: readonly FinanceRow[] = Object.freeze([
  Object.freeze({
    applicantPartyId: previewIds.applicant,
    approvalExpiresAt: null,
    approvedAmountMinor: null,
    conditions: Object.freeze([
      Object.freeze({
        conditionId: "10000000-0000-4000-8000-000000000822",
        conditionKey: "proof_of_income",
        createdAt: "2026-07-16T13:10:00.000Z",
        description: "Proof of income received",
        dueAt: null,
        logicalConditionId: "10000000-0000-4000-8000-000000000823",
        replacesConditionId: null,
        required: true,
        satisfiedAt: null,
        status: "active",
        supportingFileId: null,
        version: 1,
      }),
    ]),
    customerAcceptedAt: null,
    currencyCode: "CAD",
    dealId: previewIds.dealA,
    externalReference: null,
    financeApplicationId: previewIds.finance,
    fundedAt: null,
    fundingReference: null,
    lenderPartyId: previewIds.lender,
    lenderReportedAnnualRate: null,
    lenderReportedTermMonths: null,
    notes: null,
    requestedAmountMinor: "2850000",
    status: "submitted",
    statusReason: null,
    submittedAt: "2026-07-16T13:10:00.000Z",
    updatedAt: "2026-07-16T13:10:00.000Z",
    version: 2,
  }),
]);

const previewPayments: readonly PaymentRow[] = Object.freeze([
  Object.freeze({
    amountMinor: "100000",
    correctsTransactionId: null,
    correctionReason: null,
    createdAt: "2026-07-16T12:45:00.000Z",
    currencyCode: "CAD",
    lastUpdatedByUserId: previewIds.membership,
    methodKey: "card",
    notes: "Synthetic preview deposit",
    occurredAt: "2026-07-16T12:45:00.000Z",
    paymentTransactionId: previewIds.payment,
    proofFileId: null,
    recordedByUserId: previewIds.membership,
    reference: "SYNTHETIC-PREVIEW",
    settledAt: null,
    status: "recorded",
    transactionType: "deposit",
    updatedAt: "2026-07-16T12:45:00.000Z",
    version: 1,
  }),
]);

const previewParticipants: readonly ParticipantRow[] = Object.freeze([
  Object.freeze({
    isPrimary: true,
    participantId: previewIds.participant,
    partyDisplayName: "Maya Okonkwo",
    partyId: previewIds.applicant,
    roleKey: "buyer",
    status: "active",
    version: 1,
  }),
]);

const previewInventoryLinks: readonly InventoryLinkRow[] = Object.freeze([
  Object.freeze({
    amountMinor: "3200000",
    currencyCode: "CAD",
    inventoryLinkId: previewIds.inventoryLink,
    inventoryStatus: "active",
    inventoryUnitId: previewIds.inventory,
    roleKey: "sold",
    status: "active",
    stockNumber: "SYN-101",
    version: 1,
  }),
]);

const previewLineItems: readonly LineItemRow[] = Object.freeze([
  Object.freeze({
    currencyCode: "CAD",
    itemType: "vehicle",
    key: "vehicle_price",
    label: "Vehicle price",
    lineItemId: previewIds.lineItem,
    paymentTimingKey: null,
    quantity: "1",
    sortOrder: 10,
    sourceKey: null,
    sourceReference: null,
    status: "active",
    taxClassificationKey: "vehicle",
    unitAmountMinor: "3200000",
    version: 1,
  }),
]);

function textValue(data: FormData, key: string): string {
  return String(data.get(key) ?? "").trim();
}

function checked(data: FormData, key: string): boolean {
  return data.get(key) === "on";
}

function previewEvidence(aggregateVersion: number): M3CommandEvidence {
  return {
    aggregateVersion,
    auditEventId: crypto.randomUUID(),
    outboxEventId: crypto.randomUUID(),
    replayed: false,
  };
}

function toIso(value: FormDataEntryValue | null): string {
  const parsed = new Date(String(value ?? ""));
  return Number.isNaN(parsed.valueOf())
    ? new Date().toISOString()
    : parsed.toISOString();
}

function toIsoOrNull(value: FormDataEntryValue | null): string | null {
  const text = String(value ?? "").trim();
  return text ? toIso(text) : null;
}

function dateTimeInput(value: string | null): string {
  return value ? value.slice(0, 16) : "";
}

function withPreview(path: string, previewMode: boolean): string {
  return previewMode ? `${path}?preview=m3` : path;
}

function dateTime(value: string, locale: Locale): string {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) return value;
  return new Intl.DateTimeFormat(locale === "fr" ? "fr-CA" : "en-CA", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "UTC",
  }).format(parsed);
}

function errorMessage(error: unknown, copy: M3Messages): string {
  return error instanceof M3ApiError
    ? `${copy.common.errorHeading} · ${error.correlationId}`
    : copy.common.errorHeading;
}

function Field({
  children,
  label,
  required = false,
}: {
  readonly children: ReactNode;
  readonly label: string;
  readonly required?: boolean;
}) {
  return (
    <label className="grid min-w-0 gap-2 text-sm font-bold">
      <span>
        {label}
        {required ? " *" : ""}
      </span>
      {children}
    </label>
  );
}

function Status({ label }: { readonly label: string }) {
  return (
    <span className="inline-flex min-h-7 w-fit items-center rounded-full border border-border bg-card px-2 text-xs font-semibold tracking-[0.06em] uppercase">
      {label}
    </span>
  );
}

function Section({
  action,
  children,
  description,
  title,
}: {
  readonly action?: ReactNode;
  readonly children: ReactNode;
  readonly description?: string | undefined;
  readonly title: string;
}) {
  return (
    <section className="border-t border-[var(--line)] first:border-t-0">
      <header className="flex flex-col gap-3 px-4 py-5 sm:flex-row sm:items-start sm:justify-between sm:px-6 lg:px-8">
        <div>
          <h2 className="m-0 min-w-0 text-xl font-bold tracking-[-0.02em] [overflow-wrap:anywhere]">
            {title}
          </h2>
          {description ? (
            <p className="mb-0 mt-1 max-w-[68ch] text-sm leading-6 text-muted-foreground">
              {description}
            </p>
          ) : null}
        </div>
        {action}
      </header>
      {children}
    </section>
  );
}

export function M3DealWorkbench({
  dealId,
  locale,
  previewMode,
  view,
}: M3DealWorkbenchProps) {
  const copy = m3Messages[locale];
  return (
    <M3OperatorRuntime
      attentionCount={2}
      copy={copy}
      current="deals"
      eyebrow={copy.deals.workflow}
      locale={locale}
      previewMode={previewMode}
      summary={copy.deals.summary}
      title={
        view === "finance"
          ? copy.deals.financeHeading
          : view === "payments"
            ? copy.deals.moneyHeading
            : view === "trade-ins"
              ? copy.deals.tradeInHeading
              : copy.deals.heading
      }
    >
      {(runtime) => (
        <DealSurface
          copy={copy}
          dealId={dealId}
          locale={locale}
          runtime={runtime}
          view={view}
        />
      )}
    </M3OperatorRuntime>
  );
}

function DealSurface({
  copy,
  dealId,
  locale,
  runtime,
  view,
}: {
  readonly copy: M3Messages;
  readonly dealId: string | undefined;
  readonly locale: Locale;
  readonly runtime: M3OperatorRuntimeState;
  readonly view: M3DealView;
}) {
  const router = useRouter();
  const [deals, setDeals] = useState<readonly DealListRow[]>(M3_PREVIEW_DEALS);
  const [deal, setDeal] = useState<DealDetailRow | null>(
    M3_PREVIEW_DEALS.find((item) => item.dealId === dealId) ??
      M3_PREVIEW_DEALS[0]!,
  );
  const [tradeIns, setTradeIns] =
    useState<readonly TradeInRow[]>(previewTradeIns);
  const [finance, setFinance] = useState<readonly FinanceRow[]>(previewFinance);
  const [payments, setPayments] =
    useState<readonly PaymentRow[]>(previewPayments);
  const [participants, setParticipants] =
    useState<readonly ParticipantRow[]>(previewParticipants);
  const [inventoryLinks, setInventoryLinks] = useState<
    readonly InventoryLinkRow[]
  >(previewInventoryLinks);
  const [lineItems, setLineItems] =
    useState<readonly LineItemRow[]>(previewLineItems);
  const [loading, setLoading] = useState(!runtime.previewMode);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refreshDeals = useCallback(async () => {
    setDeals(
      await requestM3Json<readonly DealListRow[]>({
        context: runtime.apiContext,
        path: "/api/v1/deals",
      }),
    );
  }, [runtime.apiContext]);

  const refreshDealDetail = useCallback(
    async (id: string) => {
      setDeal(
        await requestM3Json<DealDetailRow>({
          context: runtime.apiContext,
          path: `/api/v1/deals/${id}`,
        }),
      );
    },
    [runtime.apiContext],
  );

  const refreshTradeIns = useCallback(
    async (id: string) => {
      setTradeIns(
        await requestM3Json<readonly TradeInRow[]>({
          context: runtime.apiContext,
          path: `/api/v1/deals/${id}/trade-ins`,
        }),
      );
    },
    [runtime.apiContext],
  );

  const refreshFinance = useCallback(
    async (id: string) => {
      const summaries = await requestM3Json<
        readonly Pick<FinanceRow, "financeApplicationId">[]
      >({
        context: runtime.apiContext,
        path: `/api/v1/finance-applications?deal_id=${encodeURIComponent(id)}`,
      });
      setFinance(
        await Promise.all(
          summaries.map((summary) =>
            requestM3Json<FinanceRow>({
              context: runtime.apiContext,
              path: `/api/v1/finance-applications/${summary.financeApplicationId}`,
            }),
          ),
        ),
      );
    },
    [runtime.apiContext],
  );

  const refreshPayments = useCallback(
    async (id: string) => {
      setPayments(
        await requestM3Json<readonly PaymentRow[]>({
          context: runtime.apiContext,
          path: `/api/v1/deals/${id}/payment-transactions`,
        }),
      );
    },
    [runtime.apiContext],
  );

  const refreshParticipants = useCallback(
    async (id: string) => {
      setParticipants(
        await requestM3Json<readonly ParticipantRow[]>({
          context: runtime.apiContext,
          path: `/api/v1/deals/${id}/participants`,
        }),
      );
    },
    [runtime.apiContext],
  );

  const refreshInventoryLinks = useCallback(
    async (id: string) => {
      setInventoryLinks(
        await requestM3Json<readonly InventoryLinkRow[]>({
          context: runtime.apiContext,
          path: `/api/v1/deals/${id}/inventory-units`,
        }),
      );
    },
    [runtime.apiContext],
  );

  const refreshLineItems = useCallback(
    async (id: string) => {
      setLineItems(
        await requestM3Json<readonly LineItemRow[]>({
          context: runtime.apiContext,
          path: `/api/v1/deals/${id}/line-items`,
        }),
      );
    },
    [runtime.apiContext],
  );

  const refreshDealWorkspace = useCallback(
    async (id: string) => {
      await Promise.all([
        refreshDealDetail(id),
        refreshInventoryLinks(id),
        refreshLineItems(id),
        refreshParticipants(id),
      ]);
    },
    [
      refreshDealDetail,
      refreshInventoryLinks,
      refreshLineItems,
      refreshParticipants,
    ],
  );

  useEffect(() => {
    if (runtime.previewMode || view === "deal-new") {
      return;
    }
    let active = true;
    const id = dealId ?? "";
    const load = Promise.resolve().then(async () => {
      if (view === "deals") await refreshDeals();
      else if (view === "deal-detail") await refreshDealWorkspace(id);
      else if (view === "finance")
        await Promise.all([refreshDealDetail(id), refreshFinance(id)]);
      else if (view === "payments")
        await Promise.all([refreshDealDetail(id), refreshPayments(id)]);
      else await Promise.all([refreshDealDetail(id), refreshTradeIns(id)]);
    });
    void load
      .catch((caught: unknown) => {
        if (active) setError(errorMessage(caught, copy));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [
    copy,
    dealId,
    refreshDealDetail,
    refreshDeals,
    refreshFinance,
    refreshDealWorkspace,
    refreshInventoryLinks,
    refreshLineItems,
    refreshParticipants,
    refreshPayments,
    refreshTradeIns,
    runtime.previewMode,
    runtime.selectedWorkspaceId,
    view,
  ]);

  async function command<T>(
    path: string,
    body: unknown,
    previewResult: T,
    refresh: (result: T) => Promise<void>,
    method: M3MutationMethod = "POST",
  ): Promise<T | null> {
    setSaving(true);
    setSaved(false);
    setError(null);
    try {
      const result = await runM3DealMutation({
        execute: () =>
          requestM3Json<T>({
            body,
            context: runtime.apiContext,
            method,
            path,
          }),
        previewMode: runtime.previewMode,
        previewResult,
        refresh,
      });
      setSaved(true);
      return result;
    } catch (caught) {
      setError(errorMessage(caught, copy));
      return null;
    } finally {
      setSaving(false);
    }
  }

  if (loading)
    return (
      <div
        className="flex min-h-64 items-center justify-center gap-3"
        role="status"
      >
        <LoaderCircle
          className="animate-spin motion-reduce:animate-none"
          size={20}
        />
        {copy.common.loading}
      </div>
    );

  const status = (
    <M3InlineStatus
      copy={copy.common}
      error={error}
      saved={saved}
      saving={saving}
    />
  );

  if (view === "deal-new") {
    return (
      <DealCreate
        copy={copy}
        onCreate={async (draft) => {
          setSaving(true);
          setSaved(false);
          setError(null);
          try {
            const created = runtime.previewMode
              ? { aggregateVersion: 1, dealId: previewIds.dealA }
              : await requestM3Json<{
                  readonly aggregateVersion: number;
                  readonly dealId: string;
                }>({
                  body: {
                    currencyCode: draft.currencyCode,
                    dealTypeKey: draft.dealTypeKey,
                    legalEntityId: draft.legalEntityId,
                    locationId: draft.locationId,
                    notes: draft.notes || null,
                    originatingLeadId: null,
                    ownerMembershipId: draft.ownerMembershipId || null,
                  },
                  context: runtime.apiContext,
                  method: "POST",
                  path: "/api/v1/deals",
                });
            let expectedVersion = created.aggregateVersion;
            if (!runtime.previewMode && draft.participantPartyId) {
              const participant = await requestM3Json<{
                readonly aggregateVersion: number;
              }>({
                body: {
                  expectedVersion,
                  isPrimary: true,
                  partyId: draft.participantPartyId,
                  roleKey: draft.participantRole,
                },
                context: runtime.apiContext,
                method: "POST",
                path: `/api/v1/deals/${created.dealId}/participants`,
              });
              expectedVersion = participant.aggregateVersion;
            }
            if (!runtime.previewMode && draft.inventoryUnitId) {
              await requestM3Json({
                body: {
                  expectedVersion,
                  inventoryUnitId: draft.inventoryUnitId,
                  metadata: {},
                  money: null,
                  roleKey: draft.inventoryRole,
                },
                context: runtime.apiContext,
                method: "POST",
                path: `/api/v1/deals/${created.dealId}/inventory-units`,
              });
            }
            if (!runtime.previewMode) {
              await refreshDealDetail(created.dealId);
            }
            setSaved(true);
            router.push(
              withPreview(`/deals/${created.dealId}`, runtime.previewMode),
            );
          } catch (caught) {
            setError(errorMessage(caught, copy));
          } finally {
            setSaving(false);
          }
        }}
        previewMode={runtime.previewMode}
        runtime={runtime}
        status={status}
      />
    );
  }

  if (view === "deal-detail") {
    return (
      <DealDetail
        copy={copy}
        deal={deal}
        inventoryLinks={inventoryLinks}
        lineItems={lineItems}
        locale={locale}
        onAddInventory={async (event) => {
          event.preventDefault();
          if (!deal) return;
          const form = event.currentTarget;
          const data = new FormData(form);
          const inventoryLinkId = crypto.randomUUID();
          const amountMinor = textValue(data, "amountMinor") || null;
          const inventoryUnitId = textValue(data, "inventoryUnitId");
          const roleKey = textValue(data, "roleKey");
          const result = await command<
            M3CommandEvidence & { readonly inventoryLinkId: string }
          >(
            `/api/v1/deals/${deal.dealId}/inventory-units`,
            {
              expectedVersion: deal.aggregateVersion,
              inventoryUnitId,
              metadata: {},
              money:
                amountMinor === null
                  ? null
                  : { amountMinor, currencyCode: deal.currencyCode },
              roleKey,
            },
            {
              ...previewEvidence(deal.aggregateVersion + 1),
              inventoryLinkId,
            },
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshInventoryLinks(deal.dealId),
              ]);
            },
          );
          if (result && runtime.previewMode) {
            setInventoryLinks((current) => [
              ...current,
              {
                amountMinor,
                currencyCode: amountMinor ? deal.currencyCode : null,
                inventoryLinkId: result.inventoryLinkId,
                inventoryStatus: "available",
                inventoryUnitId,
                roleKey,
                status: "active",
                stockNumber: inventoryUnitId.slice(0, 8),
                version: 1,
              },
            ]);
            setDeal((current) =>
              current
                ? { ...current, aggregateVersion: result.aggregateVersion }
                : current,
            );
            form.reset();
          }
        }}
        onAddLineItem={async (event) => {
          event.preventDefault();
          if (!deal) return;
          const form = event.currentTarget;
          const data = new FormData(form);
          const lineItemId = crypto.randomUUID();
          const itemType = textValue(
            data,
            "itemType",
          ) as LineItemRow["itemType"];
          const optimistic: LineItemRow = {
            currencyCode: deal.currencyCode,
            itemType,
            key: textValue(data, "key"),
            label: textValue(data, "label"),
            lineItemId,
            paymentTimingKey: textValue(data, "paymentTimingKey") || null,
            quantity: textValue(data, "quantity"),
            sortOrder: Number(textValue(data, "sortOrder")),
            sourceKey: textValue(data, "sourceKey") || null,
            sourceReference: textValue(data, "sourceReference") || null,
            status: "active",
            taxClassificationKey:
              textValue(data, "taxClassificationKey") || null,
            unitAmountMinor: textValue(data, "unitAmountMinor"),
            version: 1,
          };
          const result = await command<
            M3CommandEvidence & { readonly lineItemId: string }
          >(
            `/api/v1/deals/${deal.dealId}/line-items`,
            {
              expectedVersion: deal.aggregateVersion,
              itemType: optimistic.itemType,
              key: optimistic.key,
              label: optimistic.label,
              paymentTimingKey: optimistic.paymentTimingKey,
              quantity: optimistic.quantity,
              sortOrder: optimistic.sortOrder,
              sourceKey: optimistic.sourceKey,
              sourceReference: optimistic.sourceReference,
              taxClassificationKey: optimistic.taxClassificationKey,
              unitAmount: {
                amountMinor: optimistic.unitAmountMinor,
                currencyCode: deal.currencyCode,
              },
            },
            {
              ...previewEvidence(deal.aggregateVersion + 1),
              lineItemId,
            },
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshLineItems(deal.dealId),
              ]);
            },
          );
          if (result && runtime.previewMode) {
            setLineItems((current) => [
              ...current,
              { ...optimistic, lineItemId: result.lineItemId },
            ]);
            setDeal((current) =>
              current
                ? { ...current, aggregateVersion: result.aggregateVersion }
                : current,
            );
            form.reset();
          }
        }}
        onAddParticipant={async (event) => {
          event.preventDefault();
          if (!deal) return;
          const form = event.currentTarget;
          const data = new FormData(form);
          const participantId = crypto.randomUUID();
          const partyId = textValue(data, "partyId");
          const roleKey = textValue(data, "roleKey");
          const isPrimary = checked(data, "isPrimary");
          const result = await command<
            M3CommandEvidence & { readonly participantId: string }
          >(
            `/api/v1/deals/${deal.dealId}/participants`,
            {
              expectedVersion: deal.aggregateVersion,
              isPrimary,
              partyId,
              roleKey,
            },
            {
              ...previewEvidence(deal.aggregateVersion + 1),
              participantId,
            },
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshParticipants(deal.dealId),
              ]);
            },
          );
          if (result && runtime.previewMode) {
            setParticipants((current) => [
              ...current,
              {
                isPrimary,
                participantId: result.participantId,
                partyDisplayName: partyId,
                partyId,
                roleKey,
                status: "active",
                version: 1,
              },
            ]);
            setDeal((current) =>
              current
                ? { ...current, aggregateVersion: result.aggregateVersion }
                : current,
            );
            form.reset();
          }
        }}
        onReleaseInventory={async (item) => {
          if (!deal) return;
          const result = await command<void>(
            `/api/v1/deals/${deal.dealId}/inventory-units/${item.inventoryLinkId}`,
            { expectedVersion: deal.aggregateVersion },
            undefined,
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshInventoryLinks(deal.dealId),
              ]);
            },
            "DELETE",
          );
          if (result !== null && runtime.previewMode) {
            setInventoryLinks((current) =>
              current.map((row) =>
                row.inventoryLinkId === item.inventoryLinkId
                  ? { ...row, status: "released", version: row.version + 1 }
                  : row,
              ),
            );
            setDeal((current) =>
              current
                ? { ...current, aggregateVersion: current.aggregateVersion + 1 }
                : current,
            );
          }
        }}
        onReleaseParticipant={async (item) => {
          if (!deal) return;
          const result = await command<void>(
            `/api/v1/deals/${deal.dealId}/participants/${item.participantId}`,
            { expectedVersion: deal.aggregateVersion },
            undefined,
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshParticipants(deal.dealId),
              ]);
            },
            "DELETE",
          );
          if (result !== null && runtime.previewMode) {
            setParticipants((current) =>
              current.map((row) =>
                row.participantId === item.participantId
                  ? { ...row, status: "released", version: row.version + 1 }
                  : row,
              ),
            );
            setDeal((current) =>
              current
                ? { ...current, aggregateVersion: current.aggregateVersion + 1 }
                : current,
            );
          }
        }}
        onTransition={async (event) => {
          event.preventDefault();
          if (!deal) return;
          const data = new FormData(event.currentTarget);
          const transitionKey = textValue(data, "transitionKey");
          const transition = deal.availableTransitions.find(
            (item) => item.transitionKey === transitionKey,
          );
          if (!transition) return;
          const reason = textValue(data, "reason");
          if (transition.reasonRequired && !reason) {
            setError(copy.deals.transitionReasonRequired);
            return;
          }
          const result = await command<
            Readonly<{
              aggregateVersion: number;
              canonicalStatus: string;
              dealId: string;
              stateKey: string;
            }>
          >(
            `/api/v1/deals/${deal.dealId}/transition`,
            {
              expectedVersion: deal.aggregateVersion,
              reason: reason || null,
              transitionKey,
            },
            {
              aggregateVersion: deal.aggregateVersion + 1,
              canonicalStatus: deal.canonicalStatus,
              dealId: deal.dealId,
              stateKey: transition.toStateKey,
            },
            () => refreshDealDetail(deal.dealId),
          );
          if (result && runtime.previewMode)
            setDeal({
              ...deal,
              aggregateVersion: result.aggregateVersion,
              canonicalStatus: result.canonicalStatus,
              stateKey: result.stateKey,
              updatedAt: new Date().toISOString(),
            });
        }}
        onUpdateLineItem={async (event, item) => {
          event.preventDefault();
          if (!deal) return;
          const data = new FormData(event.currentTarget);
          const itemType = textValue(
            data,
            "itemType",
          ) as LineItemRow["itemType"];
          const updated: LineItemRow = {
            ...item,
            itemType,
            label: textValue(data, "label"),
            paymentTimingKey: textValue(data, "paymentTimingKey") || null,
            quantity: textValue(data, "quantity"),
            sortOrder: Number(textValue(data, "sortOrder")),
            sourceKey: textValue(data, "sourceKey") || null,
            sourceReference: textValue(data, "sourceReference") || null,
            taxClassificationKey:
              textValue(data, "taxClassificationKey") || null,
            unitAmountMinor: textValue(data, "unitAmountMinor"),
            version: item.version + 1,
          };
          const result = await command<
            M3CommandEvidence & {
              readonly lineItemId: string;
              readonly lineItemVersion: number;
            }
          >(
            `/api/v1/deal-line-items/${item.lineItemId}`,
            {
              dealId: deal.dealId,
              expectedLineItemVersion: item.version,
              expectedVersion: deal.aggregateVersion,
              itemType: updated.itemType,
              label: updated.label,
              paymentTimingKey: updated.paymentTimingKey,
              quantity: updated.quantity,
              sortOrder: updated.sortOrder,
              sourceKey: updated.sourceKey,
              sourceReference: updated.sourceReference,
              taxClassificationKey: updated.taxClassificationKey,
              unitAmount: {
                amountMinor: updated.unitAmountMinor,
                currencyCode: deal.currencyCode,
              },
            },
            {
              ...previewEvidence(deal.aggregateVersion + 1),
              lineItemId: item.lineItemId,
              lineItemVersion: item.version + 1,
            },
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshLineItems(deal.dealId),
              ]);
            },
            "PATCH",
          );
          if (result && runtime.previewMode) {
            setLineItems((current) =>
              current.map((row) =>
                row.lineItemId === item.lineItemId
                  ? { ...updated, version: result.lineItemVersion }
                  : row,
              ),
            );
            setDeal((current) =>
              current
                ? { ...current, aggregateVersion: result.aggregateVersion }
                : current,
            );
          }
        }}
        participants={participants}
        previewMode={runtime.previewMode}
        runtime={runtime}
        status={status}
      />
    );
  }

  if (view === "trade-ins") {
    return (
      <TradeInWorkbench
        copy={copy}
        deal={deal}
        locale={locale}
        onConfirmInventory={async (event, item) => {
          event.preventDefault();
          if (!deal) return;
          const data = new FormData(event.currentTarget);
          const inventoryUnitId = textValue(data, "inventoryUnitId");
          const result = await command<
            M3CommandEvidence & {
              readonly tradeInId: string;
              readonly tradeInVersion: number;
            }
          >(
            `/api/v1/trade-ins/${item.tradeInId}/confirm-inventory`,
            {
              expectedTradeInVersion: item.version,
              expectedVersion: deal.aggregateVersion,
              inventoryUnitId,
            },
            {
              ...previewEvidence(deal.aggregateVersion + 1),
              tradeInId: item.tradeInId,
              tradeInVersion: item.version + 1,
            },
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshTradeIns(deal.dealId),
              ]);
            },
          );
          if (result && runtime.previewMode) {
            setTradeIns((current) =>
              current.map((row) =>
                row.tradeInId === item.tradeInId
                  ? {
                      ...row,
                      resultingInventoryUnitId: inventoryUnitId,
                      version: result.tradeInVersion,
                    }
                  : row,
              ),
            );
            setDeal((current) =>
              current
                ? { ...current, aggregateVersion: result.aggregateVersion }
                : current,
            );
          }
        }}
        onCreate={async (event) => {
          event.preventDefault();
          if (!deal) return;
          const form = event.currentTarget;
          const data = new FormData(form);
          const currencyCode = deal.currencyCode;
          const optimisticTradeIn: TradeInRow = {
            allowanceMinor: textValue(data, "allowanceMinor"),
            conditionKey: null,
            currencyCode,
            dealId: deal.dealId,
            enteredVehicleFacts: {
              make: textValue(data, "make"),
              model: textValue(data, "model"),
              vin: textValue(data, "vin"),
              year: textValue(data, "year"),
            },
            lenderPartyId: null,
            lienAmountMinor: textValue(data, "lienMinor") || "0",
            odometerUnit: null,
            odometerValue: null,
            ownerPartyId: textValue(data, "ownerPartyId"),
            payoffAmountMinor: textValue(data, "payoffMinor") || "0",
            resultingInventoryUnitId: null,
            status: "active",
            taxEligibilityInputs: {},
            tradeInId: crypto.randomUUID(),
            vehicleId: null,
            version: 1,
          };
          const result = await command<
            M3CommandEvidence & {
              readonly tradeInId: string;
              readonly tradeInVersion: number;
            }
          >(
            `/api/v1/deals/${deal.dealId}/trade-ins`,
            {
              allowance: {
                amountMinor: textValue(data, "allowanceMinor"),
                currencyCode,
              },
              conditionKey: null,
              enteredVehicleFacts: {
                make: textValue(data, "make"),
                model: textValue(data, "model"),
                vin: textValue(data, "vin"),
                year: textValue(data, "year"),
              },
              expectedVersion: deal.aggregateVersion,
              lenderPartyId: null,
              lienAmount: {
                amountMinor: textValue(data, "lienMinor") || "0",
                currencyCode,
              },
              odometerUnit: null,
              odometerValue: null,
              ownerPartyId: textValue(data, "ownerPartyId"),
              payoffAmount: {
                amountMinor: textValue(data, "payoffMinor") || "0",
                currencyCode,
              },
              taxEligibilityInputs: {},
              vehicleId: null,
            },
            {
              ...previewEvidence(deal.aggregateVersion + 1),
              tradeInId: optimisticTradeIn.tradeInId,
              tradeInVersion: 1,
            },
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshTradeIns(deal.dealId),
              ]);
            },
          );
          if (result) {
            if (runtime.previewMode) {
              setTradeIns((current) => [
                { ...optimisticTradeIn, tradeInId: result.tradeInId },
                ...current,
              ]);
              setDeal((current) =>
                current
                  ? { ...current, aggregateVersion: result.aggregateVersion }
                  : current,
              );
            }
            form.reset();
          }
        }}
        onUpdate={async (event, item) => {
          event.preventDefault();
          if (!deal) return;
          const data = new FormData(event.currentTarget);
          const updated: TradeInRow = {
            ...item,
            allowanceMinor: textValue(data, "allowanceMinor"),
            enteredVehicleFacts: {
              make: textValue(data, "make"),
              model: textValue(data, "model"),
              vin: textValue(data, "vin"),
              year: textValue(data, "year"),
            },
            lienAmountMinor: textValue(data, "lienMinor") || "0",
            ownerPartyId: textValue(data, "ownerPartyId"),
            payoffAmountMinor: textValue(data, "payoffMinor") || "0",
            version: item.version + 1,
          };
          const result = await command<
            M3CommandEvidence & {
              readonly tradeInId: string;
              readonly tradeInVersion: number;
            }
          >(
            `/api/v1/trade-ins/${item.tradeInId}`,
            {
              allowance: {
                amountMinor: updated.allowanceMinor,
                currencyCode: deal.currencyCode,
              },
              conditionKey: item.conditionKey,
              enteredVehicleFacts: updated.enteredVehicleFacts,
              expectedTradeInVersion: item.version,
              expectedVersion: deal.aggregateVersion,
              lenderPartyId: item.lenderPartyId,
              lienAmount: {
                amountMinor: updated.lienAmountMinor,
                currencyCode: deal.currencyCode,
              },
              odometerUnit: item.odometerUnit,
              odometerValue: item.odometerValue,
              ownerPartyId: updated.ownerPartyId,
              payoffAmount: {
                amountMinor: updated.payoffAmountMinor,
                currencyCode: deal.currencyCode,
              },
              taxEligibilityInputs: item.taxEligibilityInputs,
              vehicleId: item.vehicleId,
            },
            {
              ...previewEvidence(deal.aggregateVersion + 1),
              tradeInId: item.tradeInId,
              tradeInVersion: item.version + 1,
            },
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshTradeIns(deal.dealId),
              ]);
            },
            "PATCH",
          );
          if (result && runtime.previewMode) {
            setTradeIns((current) =>
              current.map((row) =>
                row.tradeInId === item.tradeInId
                  ? { ...updated, version: result.tradeInVersion }
                  : row,
              ),
            );
            setDeal((current) =>
              current
                ? { ...current, aggregateVersion: result.aggregateVersion }
                : current,
            );
          }
        }}
        previewMode={runtime.previewMode}
        runtime={runtime}
        status={status}
        tradeIns={tradeIns}
      />
    );
  }

  if (view === "finance") {
    return (
      <FinanceWorkbench
        copy={copy}
        deal={deal}
        finance={finance}
        locale={locale}
        onAddCondition={async (event, application) => {
          event.preventDefault();
          const form = event.currentTarget;
          const data = new FormData(form);
          const conditionId = crypto.randomUUID();
          const condition: FinanceConditionRow = {
            conditionId,
            conditionKey: textValue(data, "conditionKey"),
            createdAt: new Date().toISOString(),
            description: textValue(data, "description"),
            dueAt: toIsoOrNull(data.get("dueAt")),
            logicalConditionId: crypto.randomUUID(),
            replacesConditionId: null,
            required: checked(data, "required"),
            satisfiedAt: toIsoOrNull(data.get("satisfiedAt")),
            status: "active",
            supportingFileId: textValue(data, "supportingFileId") || null,
            version: 1,
          };
          const result = await command<
            M3CommandEvidence & {
              readonly conditionId: string;
              readonly financeApplicationId: string;
            }
          >(
            `/api/v1/finance-applications/${application.financeApplicationId}/conditions`,
            {
              conditionKey: condition.conditionKey,
              description: condition.description,
              dueAt: condition.dueAt,
              expectedVersion: application.version,
              required: condition.required,
              satisfiedAt: condition.satisfiedAt,
              supportingFileId: condition.supportingFileId,
            },
            {
              ...previewEvidence(application.version + 1),
              conditionId,
              financeApplicationId: application.financeApplicationId,
            },
            async () => {
              if (!deal) return;
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshFinance(deal.dealId),
              ]);
            },
          );
          if (result && runtime.previewMode) {
            setFinance((current) =>
              current.map((item) =>
                item.financeApplicationId === application.financeApplicationId
                  ? {
                      ...item,
                      conditions: [
                        ...item.conditions,
                        { ...condition, conditionId: result.conditionId },
                      ],
                      version: result.aggregateVersion,
                    }
                  : item,
              ),
            );
            form.reset();
          }
        }}
        onCreate={async (event) => {
          event.preventDefault();
          if (!deal) return;
          const form = event.currentTarget;
          const data = new FormData(form);
          const optimisticFinance: FinanceRow = {
            applicantPartyId: textValue(data, "applicantPartyId"),
            approvalExpiresAt: null,
            approvedAmountMinor: null,
            conditions: [],
            customerAcceptedAt: null,
            currencyCode: deal.currencyCode,
            dealId: deal.dealId,
            externalReference: textValue(data, "externalReference") || null,
            financeApplicationId: crypto.randomUUID(),
            fundedAt: null,
            fundingReference: null,
            lenderPartyId: textValue(data, "lenderPartyId"),
            lenderReportedAnnualRate: textValue(data, "annualRate") || null,
            lenderReportedTermMonths: textValue(data, "termMonths")
              ? Number(textValue(data, "termMonths"))
              : null,
            notes: textValue(data, "notes") || null,
            requestedAmountMinor: textValue(data, "amountMinor"),
            status: "preparing",
            statusReason: null,
            submittedAt: null,
            updatedAt: new Date().toISOString(),
            version: 1,
          };
          const result = await command<
            M3CommandEvidence & {
              readonly financeApplicationId: string;
              readonly status: string;
            }
          >(
            "/api/v1/finance-applications",
            {
              applicantPartyId: textValue(data, "applicantPartyId"),
              dealId,
              externalReference: textValue(data, "externalReference") || null,
              lenderPartyId: textValue(data, "lenderPartyId"),
              lenderReportedAnnualRate: textValue(data, "annualRate") || null,
              lenderReportedTermMonths: textValue(data, "termMonths")
                ? Number(textValue(data, "termMonths"))
                : null,
              notes: textValue(data, "notes") || null,
              requestedAmount: {
                amountMinor: textValue(data, "amountMinor"),
                currencyCode: deal.currencyCode,
              },
            },
            {
              ...previewEvidence(1),
              financeApplicationId: optimisticFinance.financeApplicationId,
              status: "preparing",
            },
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshFinance(deal.dealId),
              ]);
            },
          );
          if (result) {
            if (runtime.previewMode) {
              setFinance((current) => [
                {
                  ...optimisticFinance,
                  financeApplicationId: result.financeApplicationId,
                  status: result.status,
                },
                ...current,
              ]);
            }
            form.reset();
          }
        }}
        onTransition={async (event, application) => {
          event.preventDefault();
          const data = new FormData(event.currentTarget);
          const targetStatus = textValue(data, "targetStatus");
          const result = await command<
            M3CommandEvidence & {
              readonly financeApplicationId: string;
              readonly status: string;
            }
          >(
            `/api/v1/finance-applications/${application.financeApplicationId}/transition`,
            {
              expectedVersion: application.version,
              reason: textValue(data, "reason") || null,
              targetStatus,
            },
            {
              ...previewEvidence(application.version + 1),
              financeApplicationId: application.financeApplicationId,
              status: targetStatus,
            },
            async () => {
              if (!deal) return;
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshFinance(deal.dealId),
              ]);
            },
          );
          if (result && runtime.previewMode) {
            setFinance((current) =>
              current.map((item) =>
                item.financeApplicationId === application.financeApplicationId
                  ? {
                      ...item,
                      status: result.status,
                      statusReason: textValue(data, "reason") || null,
                      version: result.aggregateVersion,
                    }
                  : item,
              ),
            );
          }
        }}
        onUpdate={async (event, application) => {
          event.preventDefault();
          const data = new FormData(event.currentTarget);
          const approvedAmountMinor = textValue(data, "approvedAmountMinor");
          const result = await command<
            M3CommandEvidence & {
              readonly financeApplicationId: string;
              readonly status: string;
            }
          >(
            `/api/v1/finance-applications/${application.financeApplicationId}`,
            {
              approvalExpiresAt: toIsoOrNull(data.get("approvalExpiresAt")),
              approvedAmount: approvedAmountMinor
                ? {
                    amountMinor: approvedAmountMinor,
                    currencyCode: application.currencyCode,
                  }
                : null,
              customerAcceptedAt: toIsoOrNull(data.get("customerAcceptedAt")),
              expectedVersion: application.version,
              externalReference: textValue(data, "externalReference") || null,
              fundedAt: toIsoOrNull(data.get("fundedAt")),
              fundingReference: textValue(data, "fundingReference") || null,
              lenderReportedAnnualRate: textValue(data, "annualRate") || null,
              lenderReportedTermMonths: textValue(data, "termMonths")
                ? Number(textValue(data, "termMonths"))
                : null,
              notes: textValue(data, "notes") || null,
              submittedAt: toIsoOrNull(data.get("submittedAt")),
            },
            {
              ...previewEvidence(application.version + 1),
              financeApplicationId: application.financeApplicationId,
              status: application.status,
            },
            async () => {
              if (!deal) return;
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshFinance(deal.dealId),
              ]);
            },
            "PATCH",
          );
          if (result && runtime.previewMode) {
            setFinance((current) =>
              current.map((item) =>
                item.financeApplicationId === application.financeApplicationId
                  ? {
                      ...item,
                      approvalExpiresAt: toIsoOrNull(
                        data.get("approvalExpiresAt"),
                      ),
                      approvedAmountMinor: approvedAmountMinor || null,
                      customerAcceptedAt: toIsoOrNull(
                        data.get("customerAcceptedAt"),
                      ),
                      externalReference:
                        textValue(data, "externalReference") || null,
                      fundedAt: toIsoOrNull(data.get("fundedAt")),
                      fundingReference:
                        textValue(data, "fundingReference") || null,
                      lenderReportedAnnualRate:
                        textValue(data, "annualRate") || null,
                      lenderReportedTermMonths: textValue(data, "termMonths")
                        ? Number(textValue(data, "termMonths"))
                        : null,
                      notes: textValue(data, "notes") || null,
                      submittedAt: toIsoOrNull(data.get("submittedAt")),
                      version: result.aggregateVersion,
                    }
                  : item,
              ),
            );
          }
        }}
        onUpdateCondition={async (event, application, condition) => {
          event.preventDefault();
          const data = new FormData(event.currentTarget);
          const satisfiedAt = toIsoOrNull(data.get("satisfiedAt"));
          const result = await command<
            M3CommandEvidence & {
              readonly conditionId: string;
              readonly financeApplicationId: string;
            }
          >(
            `/api/v1/finance-applications/${application.financeApplicationId}/conditions/${condition.conditionId}`,
            {
              description: textValue(data, "description"),
              dueAt: toIsoOrNull(data.get("dueAt")),
              expectedConditionVersion: condition.version,
              expectedVersion: application.version,
              required: checked(data, "required"),
              satisfiedAt,
              supportingFileId: textValue(data, "supportingFileId") || null,
            },
            {
              ...previewEvidence(application.version + 1),
              conditionId: crypto.randomUUID(),
              financeApplicationId: application.financeApplicationId,
            },
            async () => {
              if (!deal) return;
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshFinance(deal.dealId),
              ]);
            },
            "PATCH",
          );
          if (result && runtime.previewMode) {
            setFinance((current) =>
              current.map((item) =>
                item.financeApplicationId === application.financeApplicationId
                  ? {
                      ...item,
                      conditions: item.conditions.map((row) =>
                        row.conditionId === condition.conditionId
                          ? {
                              ...row,
                              conditionId: result.conditionId,
                              description: textValue(data, "description"),
                              dueAt: toIsoOrNull(data.get("dueAt")),
                              replacesConditionId: condition.conditionId,
                              required: checked(data, "required"),
                              satisfiedAt,
                              supportingFileId:
                                textValue(data, "supportingFileId") || null,
                              version: condition.version + 1,
                            }
                          : row,
                      ),
                      version: result.aggregateVersion,
                    }
                  : item,
              ),
            );
          }
        }}
        runtime={runtime}
        status={status}
      />
    );
  }

  if (view === "payments") {
    return (
      <PaymentWorkbench
        copy={copy}
        deal={deal}
        locale={locale}
        onCorrect={async (event, payment) => {
          event.preventDefault();
          const data = new FormData(event.currentTarget);
          const correctionType = textValue(data, "correctionType");
          const correctionAmountMinor = textValue(data, "amountMinor");
          const correctionReason = textValue(data, "reason");
          if (correctionType !== "refund" && correctionType !== "reversal") {
            setSaved(false);
            setError(copy.common.errorHeading);
            return;
          }
          const previewRemainingMinor = runtime.previewMode
            ? previewPaymentCorrectionRemainingMinor({
                amountMinor: correctionAmountMinor,
                correctionType,
                ledger: payments,
                payment,
              })
            : null;
          if (runtime.previewMode && previewRemainingMinor === null) {
            setSaved(false);
            setError(copy.common.errorHeading);
            return;
          }
          const correctedAt = new Date().toISOString();
          const result = await command<
            M3CommandEvidence & {
              readonly correctionTransactionId: string;
              readonly originalTransactionId: string;
              readonly remainingMinor: string;
              readonly status: string;
            }
          >(
            `/api/v1/payment-transactions/${payment.paymentTransactionId}/${correctionType === "refund" ? "refund" : "reverse"}`,
            {
              expectedVersion: payment.version,
              money: {
                amountMinor: correctionAmountMinor,
                currencyCode: payment.currencyCode,
              },
              reason: correctionReason,
            },
            {
              ...previewEvidence(payment.version + 1),
              correctionTransactionId: crypto.randomUUID(),
              originalTransactionId: payment.paymentTransactionId,
              remainingMinor: previewRemainingMinor ?? "0",
              status: "settled",
            },
            async () => {
              if (!deal) return;
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshPayments(deal.dealId),
              ]);
            },
          );
          if (result && runtime.previewMode)
            setPayments((current) => [
              {
                amountMinor: `-${correctionAmountMinor}`,
                correctsTransactionId: result.originalTransactionId,
                correctionReason,
                createdAt: correctedAt,
                currencyCode: payment.currencyCode,
                lastUpdatedByUserId: previewIds.membership,
                methodKey: null,
                notes: null,
                occurredAt: correctedAt,
                paymentTransactionId: result.correctionTransactionId,
                proofFileId: null,
                recordedByUserId: previewIds.membership,
                reference: null,
                settledAt: correctedAt,
                status: result.status,
                transactionType: correctionType,
                updatedAt: correctedAt,
                version: 1,
              },
              ...current,
            ]);
        }}
        onCreate={async (event) => {
          event.preventDefault();
          if (!deal) return;
          const form = event.currentTarget;
          const data = new FormData(form);
          const occurredAt = toIso(data.get("occurredAt"));
          const optimisticPayment: PaymentRow = {
            amountMinor: textValue(data, "amountMinor"),
            correctsTransactionId: null,
            correctionReason: null,
            createdAt: occurredAt,
            currencyCode: deal.currencyCode,
            lastUpdatedByUserId: previewIds.membership,
            methodKey: textValue(data, "methodKey"),
            notes: textValue(data, "notes") || null,
            occurredAt,
            paymentTransactionId: crypto.randomUUID(),
            proofFileId: textValue(data, "proofFileId") || null,
            recordedByUserId: previewIds.membership,
            reference: textValue(data, "reference") || null,
            settledAt: null,
            status: "recorded",
            transactionType: textValue(data, "transactionType"),
            updatedAt: occurredAt,
            version: 1,
          };
          const result = await command<
            M3CommandEvidence & {
              readonly paymentTransactionId: string;
              readonly status: string;
            }
          >(
            `/api/v1/deals/${deal.dealId}/payment-transactions`,
            {
              methodKey: textValue(data, "methodKey"),
              money: {
                amountMinor: textValue(data, "amountMinor"),
                currencyCode: deal.currencyCode,
              },
              notes: textValue(data, "notes") || null,
              occurredAt,
              proofFileId: textValue(data, "proofFileId") || null,
              reference: textValue(data, "reference") || null,
              type: textValue(data, "transactionType"),
            },
            {
              ...previewEvidence(1),
              paymentTransactionId: optimisticPayment.paymentTransactionId,
              status: "recorded",
            },
            async () => {
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshPayments(deal.dealId),
              ]);
            },
          );
          if (result) {
            if (runtime.previewMode) {
              setPayments((current) => [
                {
                  ...optimisticPayment,
                  paymentTransactionId: result.paymentTransactionId,
                  status: result.status,
                },
                ...current,
              ]);
            }
            form.reset();
          }
        }}
        onSettle={async (payment) => {
          const settledAt = new Date().toISOString();
          const result = await command<
            M3CommandEvidence & {
              readonly paymentTransactionId: string;
              readonly status: string;
            }
          >(
            `/api/v1/payment-transactions/${payment.paymentTransactionId}/settle`,
            { expectedVersion: payment.version, settledAt },
            {
              ...previewEvidence(payment.version + 1),
              paymentTransactionId: payment.paymentTransactionId,
              status: "settled",
            },
            async () => {
              if (!deal) return;
              await Promise.all([
                refreshDealDetail(deal.dealId),
                refreshPayments(deal.dealId),
              ]);
            },
          );
          if (result && runtime.previewMode)
            setPayments((current) =>
              current.map((item) =>
                item.paymentTransactionId === payment.paymentTransactionId
                  ? {
                      ...item,
                      lastUpdatedByUserId: previewIds.membership,
                      settledAt,
                      status: result.status,
                      updatedAt: settledAt,
                      version: item.version + 1,
                    }
                  : item,
              ),
            );
        }}
        payments={payments}
        runtime={runtime}
        status={status}
      />
    );
  }

  return (
    <DealList
      copy={copy}
      deals={deals}
      error={error}
      locale={locale}
      previewMode={runtime.previewMode}
    />
  );
}

interface DealDraft {
  readonly currencyCode: string;
  readonly dealTypeKey: string;
  readonly inventoryRole: string;
  readonly inventoryUnitId: string;
  readonly legalEntityId: string;
  readonly locationId: string;
  readonly notes: string;
  readonly ownerMembershipId: string;
  readonly participantPartyId: string;
  readonly participantRole: string;
}

function DealCreate({
  copy,
  onCreate,
  previewMode,
  runtime,
  status,
}: {
  readonly copy: M3Messages;
  readonly onCreate: (draft: DealDraft) => void;
  readonly previewMode: boolean;
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
}) {
  const [step, setStep] = useState(0);
  const [draft, setDraft] = useState<DealDraft>({
    currencyCode: "CAD",
    dealTypeKey: "retail.cash",
    inventoryRole: "sold",
    inventoryUnitId: runtime.previewMode ? previewIds.inventory : "",
    legalEntityId: runtime.previewMode ? previewIds.legalEntity : "",
    locationId: runtime.previewMode ? previewIds.location : "",
    notes: "",
    ownerMembershipId: runtime.previewMode ? previewIds.membership : "",
    participantPartyId: runtime.previewMode ? previewIds.applicant : "",
    participantRole: "buyer",
  });
  const steps = [
    copy.deals.dealType,
    copy.deals.participants,
    copy.deals.inventory,
    copy.deals.review,
  ];
  const update = (key: keyof DealDraft, value: string) =>
    setDraft((current) => ({ ...current, [key]: value }));
  return (
    <Section
      description={copy.deals.emptyDescription}
      title={copy.deals.newDeal}
    >
      <div
        className="px-4 pb-8 sm:px-6 lg:px-8"
        data-testid="T-DEAL-create-step"
      >
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
          <Link
            className={m3LinkButtonClass}
            href={withPreview("/deals", previewMode)}
          >
            <ArrowLeft aria-hidden="true" size={16} />
            {copy.common.back}
          </Link>
          <p className="m-0 text-sm font-bold">
            {copy.deals.step} {step + 1} / {steps.length} · {steps[step]}
          </p>
        </div>
        <div className="mb-6 grid h-1 grid-cols-4 gap-1" aria-hidden="true">
          {steps.map((label, index) => (
            <span
              className={
                index <= step ? "bg-[var(--signal)]" : "bg-[var(--line)]"
              }
              key={label}
            />
          ))}
        </div>
        {step === 0 ? (
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label={copy.deals.dealType} required>
              <Input
                className={m3FieldClass}
                onChange={(event) => update("dealTypeKey", event.target.value)}
                value={draft.dealTypeKey}
              />
            </Field>
            <Field label={copy.deals.currency} required>
              <Input
                className={m3FieldClass}
                maxLength={3}
                onChange={(event) =>
                  update("currencyCode", event.target.value.toUpperCase())
                }
                value={draft.currencyCode}
              />
            </Field>
            <Field label={copy.crm.locationId} required>
              <Input
                className={m3FieldClass}
                onChange={(event) => update("locationId", event.target.value)}
                value={draft.locationId}
              />
            </Field>
            <Field label={copy.crm.legalEntityId} required>
              <Input
                className={m3FieldClass}
                onChange={(event) =>
                  update("legalEntityId", event.target.value)
                }
                value={draft.legalEntityId}
              />
            </Field>
            <Field label={copy.crm.ownerMembershipId}>
              <Input
                className={m3FieldClass}
                onChange={(event) =>
                  update("ownerMembershipId", event.target.value)
                }
                value={draft.ownerMembershipId}
              />
            </Field>
            <div className="sm:col-span-2">
              <Field label={copy.deals.notes}>
                <Textarea
                  className={m3TextAreaClass}
                  onChange={(event) => update("notes", event.target.value)}
                  value={draft.notes}
                />
              </Field>
            </div>
          </div>
        ) : null}
        {step === 1 ? (
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label={copy.deals.participantPartyId}>
              <Input
                className={m3FieldClass}
                onChange={(event) =>
                  update("participantPartyId", event.target.value)
                }
                value={draft.participantPartyId}
              />
            </Field>
            <Field label={copy.deals.participantRole}>
              <Input
                className={m3FieldClass}
                onChange={(event) =>
                  update("participantRole", event.target.value)
                }
                value={draft.participantRole}
              />
            </Field>
          </div>
        ) : null}
        {step === 2 ? (
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label={copy.deals.inventoryUnitId}>
              <Input
                className={m3FieldClass}
                onChange={(event) =>
                  update("inventoryUnitId", event.target.value)
                }
                value={draft.inventoryUnitId}
              />
            </Field>
            <Field label={copy.deals.inventoryRole}>
              <Input
                className={m3FieldClass}
                onChange={(event) =>
                  update("inventoryRole", event.target.value)
                }
                value={draft.inventoryRole}
              />
            </Field>
          </div>
        ) : null}
        {step === 3 ? (
          <dl className="grid border border-[var(--line)] sm:grid-cols-2">
            {[
              [copy.deals.dealType, draft.dealTypeKey],
              [copy.deals.currency, draft.currencyCode],
              [copy.deals.participants, draft.participantPartyId || "—"],
              [copy.deals.inventory, draft.inventoryUnitId || "—"],
            ].map(([term, value]) => (
              <div
                className="border-b border-[var(--line)] p-4 last:border-b-0 sm:border-r"
                key={term}
              >
                <dt className="text-xs font-bold uppercase tracking-[0.08em] text-muted-foreground">
                  {term}
                </dt>
                <dd className="mb-0 ml-0 mt-2 break-all text-sm">{value}</dd>
              </div>
            ))}
          </dl>
        ) : null}
        <div className="mt-6 flex flex-wrap items-center gap-3">
          {step > 0 ? (
            <Button
              className={m3SecondaryButtonClass}
              onClick={() => setStep((value) => value - 1)}
              type="button"
            >
              <ArrowLeft aria-hidden="true" size={16} />
              {copy.common.back}
            </Button>
          ) : null}
          {step < steps.length - 1 ? (
            <Button
              className={m3PrimaryButtonClass}
              disabled={
                step === 0 &&
                (!draft.dealTypeKey ||
                  !draft.currencyCode ||
                  !draft.locationId ||
                  !draft.legalEntityId)
              }
              onClick={() => setStep((value) => value + 1)}
              type="button"
            >
              {copy.common.continue}
              <ArrowRight aria-hidden="true" size={16} />
            </Button>
          ) : (
            <Button
              className={m3PrimaryButtonClass}
              disabled={!runtime.canWrite}
              onClick={() => onCreate(draft)}
              type="button"
            >
              <Check aria-hidden="true" size={16} />
              {copy.deals.createDeal}
            </Button>
          )}
          {status}
        </div>
      </div>
    </Section>
  );
}

function DealList({
  copy,
  deals,
  error,
  locale,
  previewMode,
}: {
  readonly copy: M3Messages;
  readonly deals: readonly DealListRow[];
  readonly error: string | null;
  readonly locale: Locale;
  readonly previewMode: boolean;
}) {
  return (
    <Section
      action={
        <Link
          className={m3PrimaryButtonClass}
          href={withPreview("/deals/new", previewMode)}
        >
          <Plus aria-hidden="true" size={18} />
          {copy.deals.newDeal}
        </Link>
      }
      description={copy.deals.emptyDescription}
      title={copy.deals.dealCount(deals.length)}
    >
      {error ? (
        <p
          className="m-0 px-4 py-4 text-sm font-bold text-[var(--rust)]"
          role="alert"
        >
          {error}
        </p>
      ) : null}
      {deals.length === 0 ? (
        <div className="px-4 py-14 sm:px-6 lg:px-8">
          <h3 className="m-0 text-xl">{copy.deals.emptyHeading}</h3>
          <p className="mb-0 mt-2 text-sm text-muted-foreground">
            {copy.deals.emptyDescription}
          </p>
        </div>
      ) : (
        <div>
          {deals.map((item) => (
            <article
              className="grid gap-4 border-b border-[var(--line)] px-4 py-5 last:border-b-0 sm:grid-cols-[minmax(0,1fr)_minmax(11rem,0.4fr)_auto] sm:items-center sm:px-6 lg:px-8"
              key={item.dealId}
            >
              <div>
                <Status
                  label={
                    copy.deals.stateLabels[item.stateKey] ??
                    copy.deals.statusUnavailable
                  }
                />
                <h3 className="mb-0 mt-2 text-base font-bold">
                  {item.dealTypeLabels[locale] ?? item.dealTypeLabels.en}
                </h3>
                <p className="mb-0 mt-1 text-xs text-muted-foreground">
                  {item.dealId}
                </p>
              </div>
              <div>
                <p className="m-0 text-xs font-bold uppercase tracking-[0.08em] text-muted-foreground">
                  {copy.deals.updatedAt}
                </p>
                <p className="mb-0 mt-1 text-sm">
                  {dateTime(item.updatedAt, locale)}
                </p>
              </div>
              <Link
                className={m3LinkButtonClass}
                href={withPreview(`/deals/${item.dealId}`, previewMode)}
              >
                {copy.deals.openDeal}
                <ArrowRight aria-hidden="true" size={16} />
              </Link>
            </article>
          ))}
        </div>
      )}
    </Section>
  );
}

function DealNav({
  copy,
  dealId,
  previewMode,
}: {
  readonly copy: M3Messages;
  readonly dealId: string;
  readonly previewMode: boolean;
}) {
  return (
    <nav
      aria-label={copy.deals.heading}
      className="flex gap-2 overflow-x-auto border-b border-[var(--line)] px-4 py-3 sm:px-6 lg:px-8"
    >
      {[
        [copy.common.details, `/deals/${dealId}`],
        [copy.deals.tradeInHeading, `/deals/${dealId}/trade-ins`],
        [copy.deals.financeHeading, `/deals/${dealId}/finance`],
        [copy.deals.moneyHeading, `/deals/${dealId}/payments`],
      ].map(([label, href]) => (
        <Link
          className={m3LinkButtonClass}
          href={withPreview(href!, previewMode)}
          key={href}
        >
          {label}
        </Link>
      ))}
    </nav>
  );
}

function DealDetail({
  copy,
  deal,
  inventoryLinks,
  lineItems,
  locale,
  onAddInventory,
  onAddLineItem,
  onAddParticipant,
  onReleaseInventory,
  onReleaseParticipant,
  onTransition,
  onUpdateLineItem,
  participants,
  previewMode,
  runtime,
  status,
}: {
  readonly copy: M3Messages;
  readonly deal: DealDetailRow | null;
  readonly inventoryLinks: readonly InventoryLinkRow[];
  readonly lineItems: readonly LineItemRow[];
  readonly locale: Locale;
  readonly onAddInventory: (event: FormEvent<HTMLFormElement>) => void;
  readonly onAddLineItem: (event: FormEvent<HTMLFormElement>) => void;
  readonly onAddParticipant: (event: FormEvent<HTMLFormElement>) => void;
  readonly onReleaseInventory: (item: InventoryLinkRow) => void;
  readonly onReleaseParticipant: (item: ParticipantRow) => void;
  readonly onTransition: (event: FormEvent<HTMLFormElement>) => void;
  readonly onUpdateLineItem: (
    event: FormEvent<HTMLFormElement>,
    item: LineItemRow,
  ) => void;
  readonly participants: readonly ParticipantRow[];
  readonly previewMode: boolean;
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
}) {
  const [transitionKey, setTransitionKey] = useState("");
  const selectedTransition =
    deal?.availableTransitions.find(
      (item) => item.transitionKey === transitionKey,
    ) ?? deal?.availableTransitions[0];
  if (!deal) return <p className="px-4 py-12">{copy.deals.emptyHeading}</p>;
  return (
    <div>
      <DealNav copy={copy} dealId={deal.dealId} previewMode={previewMode} />
      <Section
        description={deal.notes ?? copy.deals.summary}
        title={deal.dealTypeLabels[locale] ?? deal.dealTypeLabels.en}
      >
        <dl className="grid border-y border-[var(--line)] sm:grid-cols-4">
          {[
            [
              copy.common.status,
              copy.deals.stateLabels[deal.stateKey] ??
                copy.deals.statusUnavailable,
            ],
            [copy.deals.currency, deal.currencyCode],
            [copy.deals.version, String(deal.aggregateVersion)],
            [copy.deals.updatedAt, dateTime(deal.updatedAt, locale)],
          ].map(([term, value]) => (
            <div
              className="border-b border-[var(--line)] p-4 last:border-b-0 sm:border-b-0 sm:border-r sm:px-6 sm:last:border-r-0"
              key={term}
            >
              <dt className="text-xs font-bold uppercase tracking-[0.08em] text-muted-foreground">
                {term}
              </dt>
              <dd className="mb-0 ml-0 mt-2 text-sm font-bold">{value}</dd>
            </div>
          ))}
        </dl>
      </Section>
      <Section title={copy.deals.workflow}>
        <form
          className="grid gap-4 px-4 pb-6 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto] sm:items-end sm:px-6 lg:px-8"
          onSubmit={onTransition}
        >
          <Field label={copy.crm.transitionTarget} required>
            <NativeSelect
              className={m3FieldClass}
              name="transitionKey"
              onChange={(event) => setTransitionKey(event.target.value)}
              value={selectedTransition?.transitionKey ?? ""}
            >
              {deal.availableTransitions.map((transition) => (
                <option
                  key={transition.transitionKey}
                  value={transition.transitionKey}
                >
                  {transition.labels[locale] ??
                    transition.labels.en ??
                    copy.deals.configuredOptionUnavailable}
                </option>
              ))}
            </NativeSelect>
          </Field>
          <Field
            label={copy.deals.correctionReason}
            required={selectedTransition?.reasonRequired ?? false}
          >
            <Input
              className={m3FieldClass}
              name="reason"
              required={selectedTransition?.reasonRequired ?? false}
            />
          </Field>
          <Button
            className={m3PrimaryButtonClass}
            disabled={!runtime.canWrite || !selectedTransition}
            type="submit"
          >
            {copy.common.continue}
            <ArrowRight aria-hidden="true" size={16} />
          </Button>
        </form>
        <div className="px-4 pb-5 sm:px-6 lg:px-8">{status}</div>
      </Section>
      <DealChildren
        copy={copy}
        currencyCode={deal.currencyCode}
        inventoryLinks={inventoryLinks}
        inventoryRoleOptions={deal.inventoryRoleOptions}
        lineItems={lineItems}
        locale={locale}
        onAddInventory={onAddInventory}
        onAddLineItem={onAddLineItem}
        onAddParticipant={onAddParticipant}
        onReleaseInventory={onReleaseInventory}
        onReleaseParticipant={onReleaseParticipant}
        onUpdateLineItem={onUpdateLineItem}
        participants={participants}
        participantRoleOptions={deal.participantRoleOptions}
        runtime={runtime}
      />
    </div>
  );
}

function DealChildren({
  copy,
  currencyCode,
  inventoryLinks,
  inventoryRoleOptions,
  lineItems,
  locale,
  onAddInventory,
  onAddLineItem,
  onAddParticipant,
  onReleaseInventory,
  onReleaseParticipant,
  onUpdateLineItem,
  participants,
  participantRoleOptions,
  runtime,
}: {
  readonly copy: M3Messages;
  readonly currencyCode: string;
  readonly inventoryLinks: readonly InventoryLinkRow[];
  readonly inventoryRoleOptions: readonly LocalizedDealOption[];
  readonly lineItems: readonly LineItemRow[];
  readonly locale: Locale;
  readonly onAddInventory: (event: FormEvent<HTMLFormElement>) => void;
  readonly onAddLineItem: (event: FormEvent<HTMLFormElement>) => void;
  readonly onAddParticipant: (event: FormEvent<HTMLFormElement>) => void;
  readonly onReleaseInventory: (item: InventoryLinkRow) => void;
  readonly onReleaseParticipant: (item: ParticipantRow) => void;
  readonly onUpdateLineItem: (
    event: FormEvent<HTMLFormElement>,
    item: LineItemRow,
  ) => void;
  readonly participants: readonly ParticipantRow[];
  readonly participantRoleOptions: readonly LocalizedDealOption[];
  readonly runtime: M3OperatorRuntimeState;
}) {
  return (
    <>
      <Section title={copy.deals.participants}>
        {participants.length === 0 ? (
          <p className="px-4 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.deals.noParticipants}
          </p>
        ) : (
          <div>
            {participants.map((item) => (
              <article
                className="grid gap-3 border-b border-[var(--line)] px-4 py-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center sm:px-6 lg:px-8"
                key={item.participantId}
              >
                <div className="min-w-0">
                  <Status
                    label={
                      copy.deals.participantStatusLabels[item.status] ??
                      copy.deals.statusUnavailable
                    }
                  />
                  <h3 className="mb-0 mt-2 break-words text-sm font-bold">
                    {item.partyDisplayName}
                  </h3>
                  <p className="mb-0 mt-1 break-all text-xs text-muted-foreground">
                    {localizedDealOptionLabel(
                      participantRoleOptions,
                      item.roleKey,
                      locale,
                      copy.deals.configuredOptionUnavailable,
                    )}{" "}
                    · {item.partyId}
                  </p>
                </div>
                {item.status === "active" ? (
                  <Button
                    className={m3SecondaryButtonClass}
                    disabled={!runtime.canWrite}
                    onClick={() => onReleaseParticipant(item)}
                    type="button"
                  >
                    {copy.deals.releaseParticipant}
                  </Button>
                ) : null}
              </article>
            ))}
          </div>
        )}
        <form
          className="grid gap-4 border-t border-[var(--line)] px-4 py-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={onAddParticipant}
        >
          <Field label={copy.deals.participantPartyId} required>
            <Input className={m3FieldClass} name="partyId" required />
          </Field>
          <Field label={copy.deals.participantRole} required>
            <NativeSelect
              className={m3FieldClass}
              defaultValue={participantRoleOptions[0]?.key}
              name="roleKey"
              required
            >
              {participantRoleOptions.map((option) => (
                <option key={option.key} value={option.key}>
                  {option.labels[locale] ?? option.labels.en}
                </option>
              ))}
            </NativeSelect>
          </Field>
          <label className="inline-flex min-h-11 items-center gap-2 text-sm font-bold sm:col-span-2">
            <Checkbox className="size-5" name="isPrimary" />
            {copy.deals.participantPrimary}
          </label>
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
            disabled={!runtime.canWrite || participantRoleOptions.length === 0}
            type="submit"
          >
            <Plus aria-hidden="true" size={16} />
            {copy.deals.addParticipant}
          </Button>
        </form>
      </Section>
      <Section title={copy.deals.inventory}>
        {inventoryLinks.length === 0 ? (
          <p className="px-4 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.deals.noInventory}
          </p>
        ) : (
          <div>
            {inventoryLinks.map((item) => (
              <article
                className="grid gap-3 border-b border-[var(--line)] px-4 py-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center sm:px-6 lg:px-8"
                key={item.inventoryLinkId}
              >
                <div className="min-w-0">
                  <Status
                    label={
                      copy.deals.inventoryLinkStatusLabels[item.status] ??
                      copy.deals.statusUnavailable
                    }
                  />
                  <h3 className="mb-0 mt-2 text-sm font-bold">
                    {item.stockNumber} ·{" "}
                    {localizedDealOptionLabel(
                      inventoryRoleOptions,
                      item.roleKey,
                      locale,
                      copy.deals.configuredOptionUnavailable,
                    )}
                  </h3>
                  <p className="mb-0 mt-1 break-all text-xs text-muted-foreground">
                    {copy.deals.inventoryStatusLabels[item.inventoryStatus] ??
                      copy.deals.statusUnavailable}{" "}
                    · {item.inventoryUnitId}
                    {item.amountMinor && item.currencyCode
                      ? ` · ${formatM3MinorAmount(item.amountMinor, item.currencyCode, locale)}`
                      : ""}
                  </p>
                </div>
                {item.status === "active" ? (
                  <Button
                    className={m3SecondaryButtonClass}
                    disabled={!runtime.canWrite}
                    onClick={() => onReleaseInventory(item)}
                    type="button"
                  >
                    {copy.deals.releaseInventory}
                  </Button>
                ) : null}
              </article>
            ))}
          </div>
        )}
        <form
          className="grid gap-4 border-t border-[var(--line)] px-4 py-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={onAddInventory}
        >
          <Field label={copy.deals.inventoryUnitId} required>
            <Input className={m3FieldClass} name="inventoryUnitId" required />
          </Field>
          <Field label={copy.deals.inventoryRole} required>
            <NativeSelect
              className={m3FieldClass}
              defaultValue={inventoryRoleOptions[0]?.key}
              name="roleKey"
              required
            >
              {inventoryRoleOptions.map((option) => (
                <option key={option.key} value={option.key}>
                  {option.labels[locale] ?? option.labels.en}
                </option>
              ))}
            </NativeSelect>
          </Field>
          <Field label={`${copy.deals.inventoryAmount} (${currencyCode})`}>
            <Input
              className={m3FieldClass}
              inputMode="numeric"
              name="amountMinor"
            />
          </Field>
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
            disabled={!runtime.canWrite || inventoryRoleOptions.length === 0}
            type="submit"
          >
            <Plus aria-hidden="true" size={16} />
            {copy.deals.addInventory}
          </Button>
        </form>
      </Section>
      <Section title={copy.deals.lineItems}>
        {lineItems.length === 0 ? (
          <p className="px-4 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.deals.noLineItems}
          </p>
        ) : (
          <div>
            {lineItems.map((item) => (
              <article
                className="border-b border-[var(--line)] px-4 py-5 sm:px-6 lg:px-8"
                key={item.lineItemId}
              >
                <div className="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-start">
                  <div>
                    <h3 className="m-0 text-sm font-bold">{item.label}</h3>
                    <p className="mb-0 mt-1 text-xs text-muted-foreground">
                      {item.key} · {item.itemType} · {item.quantity}
                    </p>
                  </div>
                  <strong className="text-sm">
                    {formatM3MinorAmount(
                      item.unitAmountMinor,
                      item.currencyCode,
                      locale,
                    )}
                  </strong>
                </div>
                <details className="mt-4 border border-[var(--line)]">
                  <summary className="flex min-h-11 cursor-pointer items-center px-3 text-sm font-bold">
                    {copy.deals.updateLineItem}
                  </summary>
                  <form
                    className="grid gap-4 border-t border-[var(--line)] p-3 sm:grid-cols-2"
                    onSubmit={(event) => onUpdateLineItem(event, item)}
                  >
                    <LineItemFields
                      copy={copy}
                      currencyCode={currencyCode}
                      item={item}
                    />
                    <Button
                      className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
                      disabled={!runtime.canWrite}
                      type="submit"
                    >
                      {copy.deals.updateLineItem}
                    </Button>
                  </form>
                </details>
              </article>
            ))}
          </div>
        )}
        <form
          className="grid gap-4 border-t border-[var(--line)] px-4 py-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={onAddLineItem}
        >
          <LineItemFields copy={copy} currencyCode={currencyCode} includeKey />
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
            disabled={!runtime.canWrite}
            type="submit"
          >
            <Plus aria-hidden="true" size={16} />
            {copy.deals.addLineItem}
          </Button>
        </form>
      </Section>
    </>
  );
}

function LineItemFields({
  copy,
  currencyCode,
  includeKey = false,
  item,
}: {
  readonly copy: M3Messages;
  readonly currencyCode: string;
  readonly includeKey?: boolean;
  readonly item?: LineItemRow;
}) {
  const types = [
    "vehicle",
    "fee",
    "discount",
    "accessory",
    "service",
    "other",
  ] as const;
  return (
    <>
      <Field label={copy.deals.lineItemType} required>
        <NativeSelect
          className={m3FieldClass}
          defaultValue={item?.itemType ?? "other"}
          name="itemType"
        >
          {types.map((type) => (
            <option key={type} value={type}>
              {type}
            </option>
          ))}
        </NativeSelect>
      </Field>
      {includeKey ? (
        <Field label={copy.deals.lineItemKey} required>
          <Input className={m3FieldClass} name="key" required />
        </Field>
      ) : null}
      <Field label={copy.deals.lineItemLabel} required>
        <Input
          className={m3FieldClass}
          defaultValue={item?.label ?? ""}
          name="label"
          required
        />
      </Field>
      <Field label={copy.deals.quantity} required>
        <Input
          className={m3FieldClass}
          defaultValue={item?.quantity ?? "1"}
          inputMode="decimal"
          name="quantity"
          required
        />
      </Field>
      <Field label={`${copy.deals.unitAmount} (${currencyCode})`} required>
        <Input
          className={m3FieldClass}
          defaultValue={item?.unitAmountMinor ?? ""}
          inputMode="numeric"
          name="unitAmountMinor"
          required
        />
      </Field>
      <Field label={copy.deals.sortOrder} required>
        <Input
          className={m3FieldClass}
          defaultValue={item?.sortOrder ?? 10}
          min={0}
          name="sortOrder"
          required
          type="number"
        />
      </Field>
      <Field label={copy.deals.taxClassification}>
        <Input
          className={m3FieldClass}
          defaultValue={item?.taxClassificationKey ?? ""}
          name="taxClassificationKey"
        />
      </Field>
      <Field label={copy.deals.paymentTiming}>
        <Input
          className={m3FieldClass}
          defaultValue={item?.paymentTimingKey ?? ""}
          name="paymentTimingKey"
        />
      </Field>
      <Field label={copy.deals.sourceKey}>
        <Input
          className={m3FieldClass}
          defaultValue={item?.sourceKey ?? ""}
          name="sourceKey"
        />
      </Field>
      <Field label={copy.deals.sourceReference}>
        <Input
          className={m3FieldClass}
          defaultValue={item?.sourceReference ?? ""}
          name="sourceReference"
        />
      </Field>
    </>
  );
}

function TradeInWorkbench({
  copy,
  deal,
  locale,
  onConfirmInventory,
  onCreate,
  onUpdate,
  previewMode,
  runtime,
  status,
  tradeIns,
}: {
  readonly copy: M3Messages;
  readonly deal: DealDetailRow | null;
  readonly locale: Locale;
  readonly onConfirmInventory: (
    event: FormEvent<HTMLFormElement>,
    item: TradeInRow,
  ) => void;
  readonly onCreate: (event: FormEvent<HTMLFormElement>) => void;
  readonly onUpdate: (
    event: FormEvent<HTMLFormElement>,
    item: TradeInRow,
  ) => void;
  readonly previewMode: boolean;
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
  readonly tradeIns: readonly TradeInRow[];
}) {
  const [confirmed, setConfirmed] = useState(false);
  const id = deal?.dealId ?? previewIds.dealA;
  return (
    <div data-testid="T-DEAL-trade-in">
      <DealNav copy={copy} dealId={id} previewMode={previewMode} />
      <Section
        description={copy.deals.createInventorySeparately}
        title={copy.deals.addTradeIn}
      >
        <form
          className="grid gap-4 px-4 pb-6 sm:grid-cols-2 sm:px-6 lg:grid-cols-3 lg:px-8"
          onSubmit={onCreate}
        >
          <Field label={copy.deals.tradeVin} required>
            <Input className={m3FieldClass} name="vin" required />
          </Field>
          <Field label={copy.deals.tradeMake} required>
            <Input className={m3FieldClass} name="make" required />
          </Field>
          <Field label={copy.deals.tradeModel} required>
            <Input className={m3FieldClass} name="model" required />
          </Field>
          <Field label={copy.deals.tradeYear} required>
            <Input
              className={m3FieldClass}
              inputMode="numeric"
              name="year"
              required
            />
          </Field>
          <Field label={copy.deals.participantPartyId} required>
            <Input
              className={m3FieldClass}
              defaultValue={runtime.previewMode ? previewIds.applicant : ""}
              name="ownerPartyId"
              required
            />
          </Field>
          <Field label={copy.deals.currency} required>
            <Input
              className={m3FieldClass}
              readOnly
              maxLength={3}
              name="currencyCode"
              required
              value={deal?.currencyCode ?? ""}
            />
          </Field>
          <Field label={copy.deals.allowance} required>
            <Input
              className={m3FieldClass}
              inputMode="numeric"
              name="allowanceMinor"
              required
            />
          </Field>
          <Field label={copy.deals.lien}>
            <Input
              className={m3FieldClass}
              defaultValue="0"
              inputMode="numeric"
              name="lienMinor"
            />
          </Field>
          <Field label={copy.deals.payoff}>
            <Input
              className={m3FieldClass}
              defaultValue="0"
              inputMode="numeric"
              name="payoffMinor"
            />
          </Field>
          <label className="flex min-h-12 items-start gap-3 border border-[var(--line)] bg-[var(--paper)] p-3 text-sm font-bold sm:col-span-2 lg:col-span-3">
            <Checkbox
              checked={confirmed}
              className="mt-1 size-5 shrink-0"
              onCheckedChange={(checked) => setConfirmed(checked === true)}
            />
            <span>{copy.deals.createInventorySeparately}</span>
          </label>
          <div className="flex flex-wrap items-center gap-3 sm:col-span-2 lg:col-span-3">
            <Button
              className={m3PrimaryButtonClass}
              disabled={!runtime.canWrite || !confirmed}
              type="submit"
            >
              <Plus aria-hidden="true" size={16} />
              {copy.deals.addTradeIn}
            </Button>
            {status}
          </div>
        </form>
      </Section>
      <Section title={copy.deals.tradeInHeading}>
        {tradeIns.length === 0 ? (
          <p className="px-4 pb-8 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.deals.noTradeIns}
          </p>
        ) : (
          <div>
            {tradeIns.map((item) => (
              <article
                className="border-b border-[var(--line)] px-4 py-5 last:border-b-0 sm:px-6 lg:px-8"
                key={item.tradeInId}
              >
                <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center">
                  <div>
                    <Status
                      label={
                        copy.deals.tradeInStatusLabels[item.status] ??
                        copy.deals.statusUnavailable
                      }
                    />
                    <h3 className="mb-0 mt-2 text-sm font-bold">
                      {item.enteredVehicleFacts.year}{" "}
                      {item.enteredVehicleFacts.make}{" "}
                      {item.enteredVehicleFacts.model}
                    </h3>
                    <p className="mb-0 mt-1 text-xs text-muted-foreground">
                      {item.enteredVehicleFacts.vin}
                    </p>
                  </div>
                  <p className="m-0 text-sm font-bold">
                    {formatM3MinorAmount(
                      item.allowanceMinor,
                      item.currencyCode,
                      locale,
                    )}
                  </p>
                </div>
                <details className="mt-4 border border-[var(--line)]">
                  <summary className="flex min-h-11 cursor-pointer items-center px-3 text-sm font-bold">
                    {copy.deals.editTradeIn}
                  </summary>
                  <form
                    className="grid gap-4 border-t border-[var(--line)] p-3 sm:grid-cols-2"
                    onSubmit={(event) => onUpdate(event, item)}
                  >
                    <Field label={copy.deals.tradeVin} required>
                      <Input
                        className={m3FieldClass}
                        defaultValue={item.enteredVehicleFacts.vin ?? ""}
                        name="vin"
                        required
                      />
                    </Field>
                    <Field label={copy.deals.tradeMake} required>
                      <Input
                        className={m3FieldClass}
                        defaultValue={item.enteredVehicleFacts.make ?? ""}
                        name="make"
                        required
                      />
                    </Field>
                    <Field label={copy.deals.tradeModel} required>
                      <Input
                        className={m3FieldClass}
                        defaultValue={item.enteredVehicleFacts.model ?? ""}
                        name="model"
                        required
                      />
                    </Field>
                    <Field label={copy.deals.tradeYear} required>
                      <Input
                        className={m3FieldClass}
                        defaultValue={item.enteredVehicleFacts.year ?? ""}
                        name="year"
                        required
                      />
                    </Field>
                    <Field label={copy.deals.participantPartyId} required>
                      <Input
                        className={m3FieldClass}
                        defaultValue={item.ownerPartyId}
                        name="ownerPartyId"
                        required
                      />
                    </Field>
                    <Field label={copy.deals.allowance} required>
                      <Input
                        className={m3FieldClass}
                        defaultValue={item.allowanceMinor}
                        inputMode="numeric"
                        name="allowanceMinor"
                        required
                      />
                    </Field>
                    <Field label={copy.deals.lien}>
                      <Input
                        className={m3FieldClass}
                        defaultValue={item.lienAmountMinor}
                        inputMode="numeric"
                        name="lienMinor"
                      />
                    </Field>
                    <Field label={copy.deals.payoff}>
                      <Input
                        className={m3FieldClass}
                        defaultValue={item.payoffAmountMinor}
                        inputMode="numeric"
                        name="payoffMinor"
                      />
                    </Field>
                    <Button
                      className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
                      disabled={!runtime.canWrite}
                      type="submit"
                    >
                      {copy.deals.editTradeIn}
                    </Button>
                  </form>
                </details>
                {item.resultingInventoryUnitId ? (
                  <p className="mb-0 mt-3 break-all text-xs text-muted-foreground">
                    {copy.deals.resultingInventoryUnitId}:{" "}
                    {item.resultingInventoryUnitId}
                  </p>
                ) : (
                  <details className="mt-3 border border-[var(--line)]">
                    <summary className="flex min-h-11 cursor-pointer items-center px-3 text-sm font-bold">
                      {copy.deals.confirmTradeInInventory}
                    </summary>
                    <form
                      className="grid gap-3 border-t border-[var(--line)] p-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end"
                      onSubmit={(event) => onConfirmInventory(event, item)}
                    >
                      <Field
                        label={copy.deals.resultingInventoryUnitId}
                        required
                      >
                        <Input
                          className={m3FieldClass}
                          name="inventoryUnitId"
                          required
                        />
                      </Field>
                      <Button
                        className={m3SecondaryButtonClass}
                        disabled={!runtime.canWrite}
                        type="submit"
                      >
                        {copy.deals.confirmTradeInInventory}
                      </Button>
                    </form>
                  </details>
                )}
              </article>
            ))}
          </div>
        )}
      </Section>
    </div>
  );
}

function FinanceWorkbench({
  copy,
  deal,
  finance,
  locale,
  onAddCondition,
  onCreate,
  onTransition,
  onUpdate,
  onUpdateCondition,
  runtime,
  status,
}: {
  readonly copy: M3Messages;
  readonly deal: DealDetailRow | null;
  readonly finance: readonly FinanceRow[];
  readonly locale: Locale;
  readonly onAddCondition: (
    event: FormEvent<HTMLFormElement>,
    application: FinanceRow,
  ) => void;
  readonly onCreate: (event: FormEvent<HTMLFormElement>) => void;
  readonly onTransition: (
    event: FormEvent<HTMLFormElement>,
    application: FinanceRow,
  ) => void;
  readonly onUpdate: (
    event: FormEvent<HTMLFormElement>,
    application: FinanceRow,
  ) => void;
  readonly onUpdateCondition: (
    event: FormEvent<HTMLFormElement>,
    application: FinanceRow,
    condition: FinanceConditionRow,
  ) => void;
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
}) {
  return (
    <div data-testid="T-FIN-workbench">
      <DealNav
        copy={copy}
        dealId={deal?.dealId ?? previewIds.dealA}
        previewMode={runtime.previewMode}
      />
      <div
        className="flex items-start gap-3 border-b border-[var(--line)] bg-[var(--ink)] px-4 py-4 text-sm leading-6 text-[var(--paper)] sm:px-6 lg:px-8"
        role="note"
      >
        <CircleAlert aria-hidden="true" className="mt-0.5 shrink-0" size={19} />
        <span>{copy.deals.financeDisclaimer}</span>
      </div>
      <Section title={copy.deals.addFinance}>
        <form
          className="grid gap-4 px-4 pb-6 sm:grid-cols-2 sm:px-6 lg:grid-cols-3 lg:px-8"
          onSubmit={onCreate}
        >
          <Field label={copy.deals.applicantPartyId} required>
            <Input
              className={m3FieldClass}
              defaultValue={runtime.previewMode ? previewIds.applicant : ""}
              name="applicantPartyId"
              required
            />
          </Field>
          <Field label={copy.deals.lenderPartyId} required>
            <Input
              className={m3FieldClass}
              defaultValue={runtime.previewMode ? previewIds.lender : ""}
              name="lenderPartyId"
              required
            />
          </Field>
          <Field label={copy.deals.requestedAmount} required>
            <Input
              className={m3FieldClass}
              inputMode="numeric"
              maxLength={19}
              name="amountMinor"
              pattern="[1-9][0-9]{0,18}"
              required
            />
          </Field>
          <Field label={copy.deals.currency} required>
            <Input
              className={m3FieldClass}
              readOnly
              maxLength={3}
              name="currencyCode"
              required
              value={deal?.currencyCode ?? ""}
            />
          </Field>
          <Field label={copy.deals.lenderReportedRate}>
            <Input
              className={m3FieldClass}
              inputMode="decimal"
              name="annualRate"
            />
          </Field>
          <Field label={copy.deals.lenderReportedTerm}>
            <Input
              className={m3FieldClass}
              inputMode="numeric"
              name="termMonths"
              type="number"
            />
          </Field>
          <Field label={copy.deals.paymentReference}>
            <Input className={m3FieldClass} name="externalReference" />
          </Field>
          <div className="sm:col-span-2">
            <Field label={copy.deals.financeNotes}>
              <Textarea className={m3TextAreaClass} name="notes" />
            </Field>
          </div>
          <div className="flex flex-wrap items-center gap-3 sm:col-span-2 lg:col-span-3">
            <Button
              className={m3PrimaryButtonClass}
              disabled={!runtime.canWrite || !deal}
              type="submit"
            >
              <BadgeDollarSign aria-hidden="true" size={18} />
              {copy.deals.recordFinance}
            </Button>
            {status}
          </div>
        </form>
      </Section>
      <Section title={copy.deals.financeHeading}>
        {finance.length === 0 ? (
          <p className="px-4 pb-8 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.deals.noFinance}
          </p>
        ) : (
          <div>
            {finance.map((item) => (
              <article
                className="border-b border-[var(--line)] px-4 py-5 last:border-b-0 sm:px-6 lg:px-8"
                key={item.financeApplicationId}
              >
                <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center">
                  <div>
                    <Status
                      label={
                        copy.deals.stateLabels[item.status] ??
                        copy.deals.statusUnavailable
                      }
                    />
                    <p className="mb-0 mt-2 text-sm font-bold">
                      {item.lenderPartyId}
                    </p>
                    <p className="mb-0 mt-1 text-xs text-muted-foreground">
                      {dateTime(item.updatedAt, locale)}
                    </p>
                  </div>
                  <p className="m-0 text-sm font-bold">
                    {formatM3MinorAmount(
                      item.requestedAmountMinor,
                      item.currencyCode,
                      locale,
                    )}
                  </p>
                </div>
                <FinanceApplicationControls
                  application={item}
                  copy={copy}
                  locale={locale}
                  onAddCondition={onAddCondition}
                  onTransition={onTransition}
                  onUpdate={onUpdate}
                  onUpdateCondition={onUpdateCondition}
                  runtime={runtime}
                />
              </article>
            ))}
          </div>
        )}
      </Section>
    </div>
  );
}

function FinanceApplicationControls({
  application,
  copy,
  locale,
  onAddCondition,
  onTransition,
  onUpdate,
  onUpdateCondition,
  runtime,
}: {
  readonly application: FinanceRow;
  readonly copy: M3Messages;
  readonly locale: Locale;
  readonly onAddCondition: (
    event: FormEvent<HTMLFormElement>,
    application: FinanceRow,
  ) => void;
  readonly onTransition: (
    event: FormEvent<HTMLFormElement>,
    application: FinanceRow,
  ) => void;
  readonly onUpdate: (
    event: FormEvent<HTMLFormElement>,
    application: FinanceRow,
  ) => void;
  readonly onUpdateCondition: (
    event: FormEvent<HTMLFormElement>,
    application: FinanceRow,
    condition: FinanceConditionRow,
  ) => void;
  readonly runtime: M3OperatorRuntimeState;
}) {
  return (
    <div className="mt-4 grid gap-3">
      <details className="border border-[var(--line)]">
        <summary className="flex min-h-11 cursor-pointer items-center px-3 text-sm font-bold">
          {copy.deals.updateFinance}
        </summary>
        <form
          className="grid gap-4 border-t border-[var(--line)] p-3 sm:grid-cols-2"
          onSubmit={(event) => onUpdate(event, application)}
        >
          <Field label={copy.deals.approvedAmount}>
            <Input
              className={m3FieldClass}
              defaultValue={application.approvedAmountMinor ?? ""}
              inputMode="numeric"
              name="approvedAmountMinor"
            />
          </Field>
          <Field label={copy.deals.approvalExpiresAt}>
            <Input
              className={m3FieldClass}
              defaultValue={dateTimeInput(application.approvalExpiresAt)}
              name="approvalExpiresAt"
              type="datetime-local"
            />
          </Field>
          <Field label={copy.deals.paymentReference}>
            <Input
              className={m3FieldClass}
              defaultValue={application.externalReference ?? ""}
              name="externalReference"
            />
          </Field>
          <Field label={copy.deals.lenderReportedRate}>
            <Input
              className={m3FieldClass}
              defaultValue={application.lenderReportedAnnualRate ?? ""}
              inputMode="decimal"
              name="annualRate"
            />
          </Field>
          <Field label={copy.deals.lenderReportedTerm}>
            <Input
              className={m3FieldClass}
              defaultValue={application.lenderReportedTermMonths ?? ""}
              inputMode="numeric"
              name="termMonths"
              type="number"
            />
          </Field>
          <Field label={copy.deals.submittedAt}>
            <Input
              className={m3FieldClass}
              defaultValue={dateTimeInput(application.submittedAt)}
              name="submittedAt"
              type="datetime-local"
            />
          </Field>
          <Field label={copy.deals.customerAcceptedAt}>
            <Input
              className={m3FieldClass}
              defaultValue={dateTimeInput(application.customerAcceptedAt)}
              name="customerAcceptedAt"
              type="datetime-local"
            />
          </Field>
          <Field label={copy.deals.fundedAt}>
            <Input
              className={m3FieldClass}
              defaultValue={dateTimeInput(application.fundedAt)}
              name="fundedAt"
              type="datetime-local"
            />
          </Field>
          <Field label={copy.deals.fundingReference}>
            <Input
              className={m3FieldClass}
              defaultValue={application.fundingReference ?? ""}
              name="fundingReference"
            />
          </Field>
          <div className="sm:col-span-2">
            <Field label={copy.deals.financeNotes}>
              <Textarea
                className={m3TextAreaClass}
                defaultValue={application.notes ?? ""}
                name="notes"
              />
            </Field>
          </div>
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
            disabled={!runtime.canWrite}
            type="submit"
          >
            {copy.deals.updateFinance}
          </Button>
        </form>
      </details>
      <FinanceStatusForm
        application={application}
        copy={copy}
        onTransition={onTransition}
        runtime={runtime}
      />
      <details className="border border-[var(--line)]">
        <summary className="flex min-h-11 cursor-pointer items-center px-3 text-sm font-bold">
          {copy.deals.conditions} ({application.conditions.length})
        </summary>
        <div className="border-t border-[var(--line)]">
          {application.conditions.map((condition) => (
            <article
              className="border-b border-[var(--line)] p-3"
              key={condition.conditionId}
            >
              <h3 className="m-0 text-sm font-bold">{condition.description}</h3>
              <p className="mb-0 mt-1 text-xs text-muted-foreground">
                {condition.satisfiedAt
                  ? `${copy.deals.conditionSatisfiedAt}: ${dateTime(condition.satisfiedAt, locale)}`
                  : copy.deals.awaitingLender}
              </p>
              <details className="mt-3 border border-[var(--line)]">
                <summary className="flex min-h-11 cursor-pointer items-center px-3 text-sm font-bold">
                  {copy.deals.updateCondition}
                </summary>
                <form
                  className="grid gap-3 border-t border-[var(--line)] p-3 sm:grid-cols-2"
                  onSubmit={(event) =>
                    onUpdateCondition(event, application, condition)
                  }
                >
                  <ConditionFields condition={condition} copy={copy} />
                  <Button
                    className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
                    disabled={!runtime.canWrite}
                    type="submit"
                  >
                    {copy.deals.updateCondition}
                  </Button>
                </form>
              </details>
            </article>
          ))}
          <form
            className="grid gap-3 p-3 sm:grid-cols-2"
            onSubmit={(event) => onAddCondition(event, application)}
          >
            <Field label={copy.deals.conditionKey} required>
              <Input className={m3FieldClass} name="conditionKey" required />
            </Field>
            <ConditionFields copy={copy} />
            <Button
              className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
              disabled={!runtime.canWrite}
              type="submit"
            >
              <Plus aria-hidden="true" size={16} />
              {copy.deals.addCondition}
            </Button>
          </form>
        </div>
      </details>
    </div>
  );
}

function FinanceStatusForm({
  application,
  copy,
  onTransition,
  runtime,
}: {
  readonly application: FinanceRow;
  readonly copy: M3Messages;
  readonly onTransition: (
    event: FormEvent<HTMLFormElement>,
    application: FinanceRow,
  ) => void;
  readonly runtime: M3OperatorRuntimeState;
}) {
  const [targetStatus, setTargetStatus] = useState("submitted");
  const reasonRequired = [
    "cancelled",
    "customer_declined",
    "declined",
  ].includes(targetStatus);
  const statuses = [
    "preparing",
    "submitted",
    "additional_information_required",
    "conditionally_approved",
    "approved",
    "declined",
    "customer_declined",
    "funded",
    "cancelled",
    "expired",
  ];
  return (
    <details className="border border-[var(--line)]">
      <summary className="flex min-h-11 cursor-pointer items-center px-3 text-sm font-bold">
        {copy.deals.changeFinanceStatus}
      </summary>
      <form
        className="grid gap-3 border-t border-[var(--line)] p-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto] sm:items-end"
        onSubmit={(event) => onTransition(event, application)}
      >
        <Field label={copy.common.status} required>
          <NativeSelect
            className={m3FieldClass}
            name="targetStatus"
            onChange={(event) => setTargetStatus(event.target.value)}
            value={targetStatus}
          >
            {statuses.map((status) => (
              <option key={status} value={status}>
                {copy.deals.stateLabels[status] ?? copy.deals.statusUnavailable}
              </option>
            ))}
          </NativeSelect>
        </Field>
        <Field label={copy.deals.statusReason} required={reasonRequired}>
          <Input
            className={m3FieldClass}
            name="reason"
            required={reasonRequired}
          />
        </Field>
        <Button
          className={m3SecondaryButtonClass}
          disabled={!runtime.canWrite}
          type="submit"
        >
          {copy.deals.changeFinanceStatus}
        </Button>
      </form>
    </details>
  );
}

function ConditionFields({
  condition,
  copy,
}: {
  readonly condition?: FinanceConditionRow;
  readonly copy: M3Messages;
}) {
  return (
    <>
      <Field label={copy.deals.conditionDescription} required>
        <Textarea
          className={m3TextAreaClass}
          defaultValue={condition?.description ?? ""}
          name="description"
          required
        />
      </Field>
      <Field label={copy.deals.conditionDueAt}>
        <Input
          className={m3FieldClass}
          defaultValue={dateTimeInput(condition?.dueAt ?? null)}
          name="dueAt"
          type="datetime-local"
        />
      </Field>
      <Field label={copy.deals.conditionSatisfiedAt}>
        <Input
          className={m3FieldClass}
          defaultValue={dateTimeInput(condition?.satisfiedAt ?? null)}
          name="satisfiedAt"
          type="datetime-local"
        />
      </Field>
      <Field label={copy.deals.supportingFileId}>
        <Input
          className={m3FieldClass}
          defaultValue={condition?.supportingFileId ?? ""}
          name="supportingFileId"
        />
      </Field>
      <label className="inline-flex min-h-11 items-center gap-2 text-sm font-bold sm:col-span-2">
        <Checkbox
          className="size-5"
          defaultChecked={condition?.required ?? false}
          name="required"
        />
        {copy.deals.conditionRequired}
      </label>
    </>
  );
}

function PaymentWorkbench({
  copy,
  deal,
  locale,
  onCorrect,
  onCreate,
  onSettle,
  payments,
  runtime,
  status,
}: {
  readonly copy: M3Messages;
  readonly deal: DealDetailRow | null;
  readonly locale: Locale;
  readonly onCorrect: (
    event: FormEvent<HTMLFormElement>,
    payment: PaymentRow,
  ) => void;
  readonly onCreate: (event: FormEvent<HTMLFormElement>) => void;
  readonly onSettle: (payment: PaymentRow) => void;
  readonly payments: readonly PaymentRow[];
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
}) {
  return (
    <div data-testid="T-PAY-workbench">
      <DealNav
        copy={copy}
        dealId={deal?.dealId ?? previewIds.dealA}
        previewMode={runtime.previewMode}
      />
      <Section title={copy.deals.addPayment}>
        <form
          className="grid gap-4 px-4 pb-6 sm:grid-cols-2 sm:px-6 lg:grid-cols-3 lg:px-8"
          onSubmit={onCreate}
        >
          <Field label={copy.deals.transactionType} required>
            <NativeSelect
              className={m3FieldClass}
              defaultValue={deal?.oneTimeEventTypeOptions[0]?.key}
              disabled={!deal || deal.oneTimeEventTypeOptions.length === 0}
              name="transactionType"
              required
            >
              {(deal?.oneTimeEventTypeOptions ?? []).map((option) => (
                <option key={option.key} value={option.key}>
                  {option.labels[locale] ?? option.labels.en}
                </option>
              ))}
            </NativeSelect>
          </Field>
          <Field label={copy.deals.paymentMethod} required>
            <Input
              className={m3FieldClass}
              defaultValue="card"
              name="methodKey"
              required
            />
          </Field>
          <Field label={copy.deals.amount} required>
            <Input
              className={m3FieldClass}
              inputMode="numeric"
              maxLength={19}
              name="amountMinor"
              pattern="[1-9][0-9]{0,18}"
              required
            />
          </Field>
          <Field label={copy.deals.currency} required>
            <Input
              className={m3FieldClass}
              readOnly
              maxLength={3}
              name="currencyCode"
              required
              value={deal?.currencyCode ?? ""}
            />
          </Field>
          <Field label={copy.deals.occurredAt} required>
            <Input
              className={m3FieldClass}
              name="occurredAt"
              required
              type="datetime-local"
            />
          </Field>
          <Field label={copy.deals.paymentReference}>
            <Input className={m3FieldClass} name="reference" />
          </Field>
          <Field label={copy.deals.paymentProof}>
            <Input
              className={m3FieldClass}
              name="proofFileId"
              pattern="[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"
            />
          </Field>
          <div className="sm:col-span-2">
            <Field label={copy.deals.paymentNotes}>
              <Textarea className={m3TextAreaClass} name="notes" />
            </Field>
          </div>
          <div className="flex flex-wrap items-center gap-3 sm:col-span-2 lg:col-span-3">
            <Button
              className={m3PrimaryButtonClass}
              disabled={
                !runtime.canWrite ||
                !deal ||
                deal.oneTimeEventTypeOptions.length === 0
              }
              type="submit"
            >
              <ReceiptText aria-hidden="true" size={18} />
              {copy.deals.recordPayment}
            </Button>
            {status}
          </div>
        </form>
      </Section>
      <Section title={copy.deals.moneyHeading}>
        {payments.length === 0 ? (
          <p className="px-4 pb-8 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.deals.noPayments}
          </p>
        ) : (
          <div>
            {payments.map((payment) => {
              const canCorrect =
                paymentCorrectableMinor(payment, payments) > 0n;
              return (
                <article
                  className="border-b border-[var(--line)] px-4 py-5 last:border-b-0 sm:px-6 lg:px-8"
                  key={payment.paymentTransactionId}
                >
                  <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-start">
                    <div>
                      <Status
                        label={
                          copy.deals.paymentStatus[payment.status] ??
                          payment.status
                        }
                      />
                      <h3 className="mb-0 mt-2 text-sm font-bold">
                        {localizedDealOptionLabel(
                          deal?.oneTimeEventTypeOptions ?? [],
                          payment.transactionType,
                          locale,
                          copy.deals.transactionTypeLabels[
                            payment.transactionType
                          ] ?? copy.deals.configuredOptionUnavailable,
                        )}{" "}
                        ·{" "}
                        {formatM3MinorAmount(
                          payment.amountMinor,
                          payment.currencyCode,
                          locale,
                        )}
                      </h3>
                      <p className="mb-0 mt-1 text-xs text-muted-foreground">
                        {dateTime(payment.occurredAt, locale)}
                      </p>
                    </div>
                    {payment.status === "recorded" ? (
                      <Button
                        className={m3SecondaryButtonClass}
                        disabled={!runtime.canWrite}
                        onClick={() => onSettle(payment)}
                        type="button"
                      >
                        <Check aria-hidden="true" size={16} />
                        {copy.deals.settle}
                      </Button>
                    ) : null}
                  </div>
                  <dl className="mt-4 grid gap-x-5 gap-y-2 text-xs sm:grid-cols-2">
                    {payment.methodKey ? (
                      <div>
                        <dt className="font-bold text-muted-foreground">
                          {copy.deals.paymentMethod}
                        </dt>
                        <dd className="mt-0.5 break-words">
                          {payment.methodKey}
                        </dd>
                      </div>
                    ) : null}
                    {payment.reference ? (
                      <div>
                        <dt className="font-bold text-muted-foreground">
                          {copy.deals.paymentReference}
                        </dt>
                        <dd className="mt-0.5 break-words">
                          {payment.reference}
                        </dd>
                      </div>
                    ) : null}
                    {payment.proofFileId ? (
                      <div>
                        <dt className="font-bold text-muted-foreground">
                          {copy.deals.paymentProof}
                        </dt>
                        <dd className="mt-0.5 break-all">
                          {payment.proofFileId}
                        </dd>
                      </div>
                    ) : null}
                    <div>
                      <dt className="font-bold text-muted-foreground">
                        {copy.deals.recordedBy}
                      </dt>
                      <dd className="mt-0.5 break-all">
                        {payment.recordedByUserId}
                      </dd>
                    </div>
                    <div>
                      <dt className="font-bold text-muted-foreground">
                        {copy.deals.lastUpdatedBy}
                      </dt>
                      <dd className="mt-0.5 break-all">
                        {payment.lastUpdatedByUserId}
                      </dd>
                    </div>
                    {payment.correctsTransactionId ? (
                      <div>
                        <dt className="font-bold text-muted-foreground">
                          {copy.deals.correctsPayment}
                        </dt>
                        <dd className="mt-0.5 break-all">
                          {payment.correctsTransactionId}
                        </dd>
                      </div>
                    ) : null}
                    {payment.notes ? (
                      <div className="sm:col-span-2">
                        <dt className="font-bold text-muted-foreground">
                          {copy.deals.paymentNotes}
                        </dt>
                        <dd className="mt-0.5 whitespace-pre-wrap break-words">
                          {payment.notes}
                        </dd>
                      </div>
                    ) : null}
                    {payment.correctionReason ? (
                      <div className="sm:col-span-2">
                        <dt className="font-bold text-muted-foreground">
                          {copy.deals.correctionReason}
                        </dt>
                        <dd className="mt-0.5 whitespace-pre-wrap break-words">
                          {payment.correctionReason}
                        </dd>
                      </div>
                    ) : null}
                  </dl>
                  {canCorrect ? (
                    <details className="mt-4 border border-[var(--line)]">
                      <summary className="flex min-h-12 cursor-pointer list-none items-center gap-2 px-3 text-sm font-bold">
                        <RefreshCcw aria-hidden="true" size={16} />
                        {copy.deals.correctPayment}
                      </summary>
                      <form
                        className="grid gap-3 border-t border-[var(--line)] p-3 sm:grid-cols-3"
                        onSubmit={(event) => onCorrect(event, payment)}
                      >
                        <Field label={copy.deals.correctionType}>
                          <NativeSelect
                            className={m3FieldClass}
                            name="correctionType"
                          >
                            <option value="refund">{copy.deals.refund}</option>
                            <option value="reversal">
                              {copy.deals.reverse}
                            </option>
                          </NativeSelect>
                        </Field>
                        <Field label={copy.deals.correctionAmount} required>
                          <Input
                            className={m3FieldClass}
                            inputMode="numeric"
                            maxLength={19}
                            name="amountMinor"
                            pattern="[1-9][0-9]{0,18}"
                            required
                          />
                        </Field>
                        <Field label={copy.deals.correctionReason} required>
                          <Input
                            className={m3FieldClass}
                            name="reason"
                            required
                          />
                        </Field>
                        <Button
                          className={`${m3PrimaryButtonClass} justify-self-start sm:col-span-3`}
                          disabled={!runtime.canWrite}
                          type="submit"
                        >
                          {copy.deals.correctPayment}
                        </Button>
                      </form>
                    </details>
                  ) : null}
                </article>
              );
            })}
          </div>
        )}
      </Section>
    </div>
  );
}
