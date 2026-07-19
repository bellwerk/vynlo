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
  CalendarDays,
  Check,
  Clock3,
  LoaderCircle,
  Plus,
} from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  type FormEvent,
  type ReactNode,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

import type { Locale } from "../i18n/messages";
import { m3Messages, type M3Messages } from "../i18n/m3-messages";
import { M3ApiError, requestM3Json } from "../lib/m3-api-client";
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

export type M3CrmView =
  | "appointments"
  | "lead-detail"
  | "lead-new"
  | "leads"
  | "parties"
  | "party-detail"
  | "tasks";

interface M3CrmWorkbenchProps {
  readonly entityId?: string;
  readonly locale: Locale;
  readonly previewMode: boolean;
  readonly view: M3CrmView;
}

interface LeadRow {
  readonly availableTransitions?: readonly {
    readonly conversionEligibleAfter?: boolean;
    readonly labels: Readonly<Record<Locale, string>>;
    readonly reasonRequired: boolean;
    readonly toStateKey: string;
    readonly transitionKey: string;
  }[];
  readonly assigneeMembershipId: string | null;
  readonly convertedDealId?: string | null;
  readonly conversionEligible?: boolean;
  readonly leadId: string;
  readonly lostReason?: string | null;
  readonly nextActionAt: string | null;
  readonly prospectPartyId: string | null;
  readonly sourceKey: string;
  readonly stateKey: string;
  readonly summary: string;
  readonly version: number;
}

interface PartyListRow {
  readonly displayName: string;
  readonly partyId: string;
  readonly partyType: "organization" | "person";
  readonly preferredLocale: "en" | "fr";
  readonly status: "active" | "archived";
  readonly version: number;
}

interface PartyDetailRow extends PartyListRow {
  readonly addresses: readonly {
    readonly addressId: string;
    readonly addressType: string;
    readonly countryCode: string;
    readonly isPrimary: boolean;
    readonly line1: string;
    readonly line2: string | null;
    readonly locality: string;
    readonly postalCode: string;
    readonly region: string;
  }[];
  readonly contacts: readonly {
    readonly contactId: string;
    readonly contactType: "email" | "phone";
    readonly consentStatus: "denied" | "granted" | "unknown" | "withdrawn";
    readonly doNotContact: boolean;
    readonly isPreferred: boolean;
    readonly isPrimary: boolean;
    readonly value: string;
  }[];
  readonly identifiers: readonly {
    readonly identifierId: string;
    readonly identifierType: string;
    readonly jurisdiction: string;
    readonly maskedValue: string;
  }[];
  readonly preferences: readonly {
    readonly allowed: boolean;
    readonly channelKey: string;
    readonly consentSource: string | null;
    readonly consentStatus: "denied" | "granted" | "unknown" | "withdrawn";
    readonly doNotContact: boolean;
    readonly preferenceId: string;
    readonly version: number;
  }[];
  readonly profile: Readonly<Record<string, string | null>>;
  readonly relationships: readonly {
    readonly effectiveFrom: string | null;
    readonly effectiveTo: string | null;
    readonly relatedPartyId: string;
    readonly relationshipId: string;
    readonly relationshipType: string;
    readonly version: number;
  }[];
}

interface TaskRow {
  readonly assigneeMembershipId: string;
  readonly dealId: string | null;
  readonly dueAt: string;
  readonly leadId: string | null;
  readonly partyId: string | null;
  readonly priority: "high" | "low" | "normal" | "urgent";
  readonly reminderAt: string | null;
  readonly state: "cancelled" | "completed" | "open";
  readonly taskId: string;
  readonly title: string;
  readonly version: number;
}

interface AppointmentRow {
  readonly appointmentId: string;
  readonly dealId: string | null;
  readonly endsAt: string;
  readonly leadId: string | null;
  readonly locationId: string | null;
  readonly startsAt: string;
  readonly status: "cancelled" | "completed" | "no_show" | "scheduled";
  readonly timezone: string;
  readonly title: string;
  readonly version: number;
}

interface ActivityRow {
  readonly activityId: string;
  readonly activityType: string;
  readonly actorUserId: string;
  readonly body: string | null;
  readonly dealId: string | null;
  readonly direction: "inbound" | "internal" | "outbound";
  readonly leadId: string | null;
  readonly occurredAt: string;
  readonly partyId: string | null;
  readonly subject: string;
}

interface M3CommandEvidence {
  readonly aggregateVersion: number;
  readonly auditEventId: string;
  readonly outboxEventId: string;
  readonly replayed: boolean;
}

type PartyMutationAction =
  | "add-address"
  | "add-contact"
  | "add-relationship"
  | "archive"
  | "preference"
  | "replace-identifier"
  | "reveal-identifier"
  | "update";

type M3MutationMethod = "DELETE" | "PATCH" | "POST";

export async function runM3CrmMutation<TResult>(input: {
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

const ids = Object.freeze({
  appointment: "10000000-0000-4000-8000-000000000951",
  deal: "10000000-0000-4000-8000-000000000801",
  leadA: "10000000-0000-4000-8000-000000000401",
  leadB: "10000000-0000-4000-8000-000000000402",
  location: "10000000-0000-4000-8000-000000000701",
  membership: "10000000-0000-4000-8000-000000000601",
  partyA: "10000000-0000-4000-8000-000000000501",
  partyB: "10000000-0000-4000-8000-000000000502",
  task: "10000000-0000-4000-8000-000000000901",
});

export const M3_PREVIEW_LEADS: readonly LeadRow[] = Object.freeze([
  Object.freeze({
    assigneeMembershipId: ids.membership,
    availableTransitions: Object.freeze([
      Object.freeze({
        conversionEligibleAfter: false,
        labels: Object.freeze({ en: "Converted", fr: "Converti" }),
        reasonRequired: false,
        toStateKey: "converted",
        transitionKey: "qualified__converted",
      }),
      Object.freeze({
        conversionEligibleAfter: false,
        labels: Object.freeze({ en: "Lost", fr: "Perdu" }),
        reasonRequired: true,
        toStateKey: "lost",
        transitionKey: "qualified__lost",
      }),
    ]),
    conversionEligible: true,
    leadId: ids.leadA,
    nextActionAt: "2026-07-16T14:30:00.000Z",
    prospectPartyId: ids.partyA,
    sourceKey: "web_referral",
    stateKey: "qualified",
    summary: "Maya Okonkwo · compact SUV enquiry",
    version: 3,
  }),
  Object.freeze({
    assigneeMembershipId: ids.membership,
    availableTransitions: Object.freeze([
      Object.freeze({
        conversionEligibleAfter: false,
        labels: Object.freeze({ en: "Appointment", fr: "Rendez-vous" }),
        reasonRequired: false,
        toStateKey: "appointment",
        transitionKey: "contacted__appointment",
      }),
      Object.freeze({
        conversionEligibleAfter: true,
        labels: Object.freeze({ en: "Qualified", fr: "Qualifié" }),
        reasonRequired: false,
        toStateKey: "qualified",
        transitionKey: "contacted__qualified",
      }),
      Object.freeze({
        conversionEligibleAfter: false,
        labels: Object.freeze({ en: "Lost", fr: "Perdu" }),
        reasonRequired: true,
        toStateKey: "lost",
        transitionKey: "contacted__lost",
      }),
    ]),
    conversionEligible: false,
    leadId: ids.leadB,
    nextActionAt: "2026-07-17T16:00:00.000Z",
    prospectPartyId: ids.partyB,
    sourceKey: "walk_in",
    stateKey: "contacted",
    summary: "Sam Tan · sedan trade-in follow-up",
    version: 2,
  }),
]);

export const M3_PREVIEW_PARTIES: readonly PartyDetailRow[] = Object.freeze([
  Object.freeze({
    addresses: Object.freeze([]),
    contacts: Object.freeze([
      Object.freeze({
        contactId: "10000000-0000-4000-8000-000000000511",
        contactType: "email",
        consentStatus: "granted",
        doNotContact: false,
        isPreferred: true,
        isPrimary: true,
        value: "maya@example.test",
      }),
      Object.freeze({
        contactId: "10000000-0000-4000-8000-000000000512",
        contactType: "phone",
        consentStatus: "unknown",
        doNotContact: false,
        isPreferred: false,
        isPrimary: false,
        value: "+1 514 555 0141",
      }),
    ]),
    displayName: "Maya Okonkwo",
    identifiers: Object.freeze([
      Object.freeze({
        identifierId: "10000000-0000-4000-8000-000000000513",
        identifierType: "driver_licence",
        jurisdiction: "CA-QC",
        maskedValue: "••••0141",
      }),
    ]),
    partyId: ids.partyA,
    partyType: "person",
    preferences: Object.freeze([]),
    preferredLocale: "en",
    profile: Object.freeze({
      birthDate: "1991-04-12",
      familyName: "Okonkwo",
      givenName: "Maya",
      preferredName: null,
    }),
    relationships: Object.freeze([]),
    status: "active",
    version: 2,
  }),
  Object.freeze({
    addresses: Object.freeze([]),
    contacts: Object.freeze([
      Object.freeze({
        contactId: "10000000-0000-4000-8000-000000000521",
        contactType: "phone",
        consentStatus: "granted",
        doNotContact: false,
        isPreferred: true,
        isPrimary: true,
        value: "+1 514 555 0188",
      }),
    ]),
    displayName: "Sam Tan",
    identifiers: Object.freeze([]),
    partyId: ids.partyB,
    partyType: "organization",
    preferences: Object.freeze([]),
    preferredLocale: "fr",
    profile: Object.freeze({
      legalName: "Sam Tan Autos",
      registrationName: null,
    }),
    relationships: Object.freeze([]),
    status: "active",
    version: 1,
  }),
]);

const previewTasks: readonly TaskRow[] = Object.freeze([
  Object.freeze({
    assigneeMembershipId: ids.membership,
    dealId: null,
    dueAt: "2026-07-16T13:00:00.000Z",
    leadId: ids.leadA,
    partyId: ids.partyA,
    priority: "normal",
    reminderAt: null,
    state: "open",
    taskId: ids.task,
    title: "Confirm Maya’s preferred delivery date",
    version: 1,
  }),
]);

const previewAppointments: readonly AppointmentRow[] = Object.freeze([
  Object.freeze({
    appointmentId: ids.appointment,
    dealId: null,
    endsAt: "2026-07-17T15:00:00.000Z",
    leadId: ids.leadB,
    locationId: ids.location,
    startsAt: "2026-07-17T14:30:00.000Z",
    status: "scheduled",
    timezone: "America/Toronto",
    title: "Vehicle review · Sam Tan",
    version: 1,
  }),
]);

const previewActivities: readonly ActivityRow[] = Object.freeze([
  Object.freeze({
    activityId: "10000000-0000-4000-8000-000000000411",
    activityType: "note",
    actorUserId: ids.membership,
    body: "Confirmed the vehicle category and preferred contact window.",
    dealId: null,
    direction: "internal",
    leadId: ids.leadA,
    occurredAt: "2026-07-16T12:10:00.000Z",
    partyId: ids.partyA,
    subject: "Qualification call",
  }),
]);

function dateTime(value: string, locale: Locale): string {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) return value;
  return new Intl.DateTimeFormat(locale === "fr" ? "fr-CA" : "en-CA", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "UTC",
  }).format(parsed);
}

function isoOrNull(value: FormDataEntryValue | null): string | null {
  const text = String(value ?? "").trim();
  if (!text) return null;
  const parsed = new Date(text);
  return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString();
}

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

function withPreview(path: string, previewMode: boolean): string {
  return previewMode ? `${path}?preview=m3` : path;
}

function errorMessage(error: unknown, copy: M3Messages): string {
  if (error instanceof M3ApiError) {
    return `${copy.common.errorHeading} · ${error.correlationId}`;
  }
  return copy.common.errorHeading;
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
    <label className="grid min-w-0 gap-2 text-sm font-bold text-[var(--ink)]">
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
    <span className="inline-flex min-h-7 w-fit items-center rounded-full border border-border bg-card px-2 text-xs font-semibold tracking-[0.06em] text-foreground uppercase">
      {label}
    </span>
  );
}

function WorkbenchSection({
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
        <div className="min-w-0">
          <h2 className="m-0 min-w-0 text-xl font-bold tracking-[-0.02em] [overflow-wrap:anywhere]">
            {title}
          </h2>
          {description ? (
            <p className="m-0 mt-1 max-w-[68ch] text-sm leading-6 text-muted-foreground">
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

export function M3CrmWorkbench({
  entityId,
  locale,
  previewMode,
  view,
}: M3CrmWorkbenchProps) {
  const copy = m3Messages[locale];
  const current =
    view === "tasks"
      ? "tasks"
      : view === "appointments"
        ? "appointments"
        : view === "parties" || view === "party-detail"
          ? "parties"
          : "leads";
  const title =
    view === "tasks"
      ? copy.crm.taskHeading
      : view === "appointments"
        ? copy.crm.appointmentHeading
        : view === "parties" || view === "party-detail"
          ? copy.common.parties
          : copy.crm.heading;

  return (
    <M3OperatorRuntime
      attentionCount={3}
      copy={copy}
      current={current}
      eyebrow={copy.crm.workflow}
      locale={locale}
      previewMode={previewMode}
      summary={copy.crm.summary}
      title={title}
    >
      {(runtime) => (
        <CrmSurface
          copy={copy}
          entityId={entityId}
          locale={locale}
          runtime={runtime}
          view={view}
        />
      )}
    </M3OperatorRuntime>
  );
}

function CrmSurface({
  copy,
  entityId,
  locale,
  runtime,
  view,
}: {
  readonly copy: M3Messages;
  readonly entityId: string | undefined;
  readonly locale: Locale;
  readonly runtime: M3OperatorRuntimeState;
  readonly view: M3CrmView;
}) {
  const router = useRouter();
  const [leads, setLeads] = useState<readonly LeadRow[]>(M3_PREVIEW_LEADS);
  const [parties, setParties] =
    useState<readonly PartyListRow[]>(M3_PREVIEW_PARTIES);
  const [tasks, setTasks] = useState<readonly TaskRow[]>(previewTasks);
  const [appointments, setAppointments] =
    useState<readonly AppointmentRow[]>(previewAppointments);
  const [activities, setActivities] =
    useState<readonly ActivityRow[]>(previewActivities);
  const [lead, setLead] = useState<LeadRow | null>(
    M3_PREVIEW_LEADS.find((item) => item.leadId === entityId) ??
      M3_PREVIEW_LEADS[0]!,
  );
  const [party, setParty] = useState<PartyDetailRow | null>(
    M3_PREVIEW_PARTIES.find((item) => item.partyId === entityId) ??
      M3_PREVIEW_PARTIES[0]!,
  );
  const [loading, setLoading] = useState(!runtime.previewMode);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [search, setSearch] = useState("");
  const [transitionTarget, setTransitionTarget] = useState("contacted");
  const [revealedIdentifier, setRevealedIdentifier] = useState<Readonly<{
    identifierId: string;
    value: string;
  }> | null>(null);

  const refreshLeads = useCallback(async () => {
    setLeads(
      await requestM3Json<readonly LeadRow[]>({
        context: runtime.apiContext,
        path: "/api/v1/leads",
      }),
    );
  }, [runtime.apiContext]);

  const refreshParties = useCallback(async () => {
    setParties(
      await requestM3Json<readonly PartyListRow[]>({
        context: runtime.apiContext,
        path: "/api/v1/parties",
      }),
    );
  }, [runtime.apiContext]);

  const refreshLeadDetail = useCallback(
    async (leadId: string) => {
      const [nextLead, nextActivities] = await Promise.all([
        requestM3Json<LeadRow>({
          context: runtime.apiContext,
          path: `/api/v1/leads/${leadId}`,
        }),
        requestM3Json<readonly ActivityRow[]>({
          context: runtime.apiContext,
          path: `/api/v1/activities?lead_id=${encodeURIComponent(leadId)}`,
        }),
      ]);
      setLead(nextLead);
      setActivities(nextActivities);
    },
    [runtime.apiContext],
  );

  const refreshPartyDetail = useCallback(
    async (partyId: string) => {
      setParty(
        await requestM3Json<PartyDetailRow>({
          context: runtime.apiContext,
          path: `/api/v1/parties/${partyId}`,
        }),
      );
    },
    [runtime.apiContext],
  );

  const refreshTasks = useCallback(async () => {
    setTasks(
      await requestM3Json<readonly TaskRow[]>({
        context: runtime.apiContext,
        path: "/api/v1/tasks",
      }),
    );
  }, [runtime.apiContext]);

  const refreshAppointments = useCallback(async () => {
    setAppointments(
      await requestM3Json<readonly AppointmentRow[]>({
        context: runtime.apiContext,
        path: "/api/v1/appointments",
      }),
    );
  }, [runtime.apiContext]);

  useEffect(() => {
    if (runtime.previewMode || view === "lead-new") {
      return;
    }
    let active = true;
    const load = Promise.resolve().then(() =>
      view === "lead-detail"
        ? refreshLeadDetail(entityId ?? "")
        : view === "party-detail"
          ? refreshPartyDetail(entityId ?? "")
          : view === "parties"
            ? refreshParties()
            : view === "tasks"
              ? refreshTasks()
              : view === "appointments"
                ? refreshAppointments()
                : refreshLeads(),
    );
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
    entityId,
    runtime.previewMode,
    refreshAppointments,
    refreshLeadDetail,
    refreshLeads,
    refreshParties,
    refreshPartyDetail,
    refreshTasks,
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
      const result = await runM3CrmMutation({
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

  async function handlePartyMutation(
    action: PartyMutationAction,
    event: FormEvent<HTMLFormElement>,
    identifierId?: string,
  ) {
    event.preventDefault();
    if (!party) return;
    const form = event.currentTarget;
    const data = new FormData(form);
    const nextVersion = party.version + 1;
    const refresh = () => refreshPartyDetail(party.partyId);

    if (action === "update") {
      const displayName = textValue(data, "displayName");
      const preferredLocale = textValue(data, "preferredLocale") as "en" | "fr";
      const profile =
        party.partyType === "person"
          ? {
              birthDate: textValue(data, "birthDate") || null,
              familyName: textValue(data, "familyName"),
              givenName: textValue(data, "givenName"),
              preferredName: textValue(data, "preferredName") || null,
            }
          : {
              legalName: textValue(data, "legalName"),
              registrationName: textValue(data, "registrationName") || null,
            };
      const result = await command<
        M3CommandEvidence & { readonly partyId: string }
      >(
        `/api/v1/parties/${party.partyId}`,
        party.partyType === "person"
          ? {
              displayName,
              expectedVersion: party.version,
              partyType: "person",
              person: profile,
              preferredLocale,
            }
          : {
              displayName,
              expectedVersion: party.version,
              organization: profile,
              partyType: "organization",
              preferredLocale,
            },
        {
          ...previewEvidence(nextVersion),
          partyId: party.partyId,
        },
        refresh,
        "PATCH",
      );
      if (result && runtime.previewMode) {
        setParty((current) =>
          current
            ? {
                ...current,
                displayName,
                preferredLocale,
                profile,
                version: result.aggregateVersion,
              }
            : current,
        );
      }
      return;
    }

    if (action === "add-contact") {
      const contactType = textValue(data, "contactType") as "email" | "phone";
      const consentStatus = textValue(data, "consentStatus") as
        "denied" | "granted" | "unknown" | "withdrawn";
      const contactId = crypto.randomUUID();
      const value = textValue(data, "value");
      const result = await command<
        M3CommandEvidence & {
          readonly contactId: string;
          readonly partyId: string;
        }
      >(
        `/api/v1/parties/${party.partyId}/contacts`,
        {
          consentSource: textValue(data, "consentSource") || null,
          consentStatus,
          contactType,
          doNotContact: checked(data, "doNotContact"),
          isPreferred: checked(data, "isPreferred"),
          isPrimary: checked(data, "isPrimary"),
          value,
        },
        {
          ...previewEvidence(nextVersion),
          contactId,
          partyId: party.partyId,
        },
        refresh,
      );
      if (result && runtime.previewMode) {
        setParty((current) =>
          current
            ? {
                ...current,
                contacts: [
                  ...current.contacts,
                  {
                    consentStatus,
                    contactId: result.contactId,
                    contactType,
                    doNotContact: checked(data, "doNotContact"),
                    isPreferred: checked(data, "isPreferred"),
                    isPrimary: checked(data, "isPrimary"),
                    value,
                  },
                ],
                version: result.aggregateVersion,
              }
            : current,
        );
        form.reset();
      }
      return;
    }

    if (action === "add-address") {
      const addressId = crypto.randomUUID();
      const address = {
        addressId,
        addressType: textValue(data, "addressType"),
        countryCode: textValue(data, "countryCode"),
        isPrimary: checked(data, "isPrimary"),
        line1: textValue(data, "line1"),
        line2: textValue(data, "line2") || null,
        locality: textValue(data, "locality"),
        postalCode: textValue(data, "postalCode"),
        region: textValue(data, "region"),
      };
      const result = await command<
        M3CommandEvidence & {
          readonly addressId: string;
          readonly partyId: string;
        }
      >(
        `/api/v1/parties/${party.partyId}/addresses`,
        {
          addressType: address.addressType,
          countryCode: address.countryCode,
          isPrimary: address.isPrimary,
          line1: address.line1,
          line2: address.line2,
          locality: address.locality,
          postalCode: address.postalCode,
          region: address.region,
        },
        {
          ...previewEvidence(nextVersion),
          addressId,
          partyId: party.partyId,
        },
        refresh,
      );
      if (result && runtime.previewMode) {
        setParty((current) =>
          current
            ? {
                ...current,
                addresses: [
                  ...current.addresses,
                  { ...address, addressId: result.addressId },
                ],
                version: result.aggregateVersion,
              }
            : current,
        );
        form.reset();
      }
      return;
    }

    if (action === "add-relationship") {
      const relationshipId = crypto.randomUUID();
      const relationship = {
        effectiveFrom: textValue(data, "effectiveFrom") || null,
        effectiveTo: textValue(data, "effectiveTo") || null,
        relatedPartyId: textValue(data, "relatedPartyId"),
        relationshipId,
        relationshipType: textValue(data, "relationshipType"),
        version: 1,
      };
      const result = await command<
        M3CommandEvidence & {
          readonly partyId: string;
          readonly relationshipId: string;
        }
      >(
        `/api/v1/parties/${party.partyId}/relationships`,
        {
          effectiveFrom: relationship.effectiveFrom,
          effectiveTo: relationship.effectiveTo,
          relatedPartyId: relationship.relatedPartyId,
          relationshipType: relationship.relationshipType,
        },
        {
          ...previewEvidence(nextVersion),
          partyId: party.partyId,
          relationshipId,
        },
        refresh,
      );
      if (result && runtime.previewMode) {
        setParty((current) =>
          current
            ? {
                ...current,
                relationships: [
                  ...current.relationships,
                  { ...relationship, relationshipId: result.relationshipId },
                ],
                version: result.aggregateVersion,
              }
            : current,
        );
        form.reset();
      }
      return;
    }

    if (action === "preference") {
      const channelKey = textValue(data, "channelKey");
      const consentStatus = textValue(data, "consentStatus") as
        "denied" | "granted" | "unknown" | "withdrawn";
      const allowed = checked(data, "allowed");
      const doNotContact = checked(data, "doNotContact");
      const preferenceId =
        party.preferences.find((item) => item.channelKey === channelKey)
          ?.preferenceId ?? crypto.randomUUID();
      const result = await command<
        M3CommandEvidence & {
          readonly partyId: string;
          readonly preferenceId: string;
        }
      >(
        `/api/v1/parties/${party.partyId}/communication-preferences`,
        {
          allowed,
          channelKey,
          consentSource: textValue(data, "consentSource") || null,
          consentStatus,
          doNotContact,
          expectedVersion: party.version,
        },
        {
          ...previewEvidence(nextVersion),
          partyId: party.partyId,
          preferenceId,
        },
        refresh,
      );
      if (result && runtime.previewMode) {
        const preference = {
          allowed,
          channelKey,
          consentSource: textValue(data, "consentSource") || null,
          consentStatus,
          doNotContact,
          preferenceId: result.preferenceId,
          version: 1,
        };
        setParty((current) =>
          current
            ? {
                ...current,
                preferences: [
                  ...current.preferences.filter(
                    (item) => item.channelKey !== channelKey,
                  ),
                  preference,
                ],
                version: result.aggregateVersion,
              }
            : current,
        );
      }
      return;
    }

    if (action === "replace-identifier") {
      const nextIdentifierId = crypto.randomUUID();
      const identifierType = textValue(data, "identifierType");
      const jurisdiction = textValue(data, "jurisdiction");
      const value = textValue(data, "value");
      const result = await command<
        M3CommandEvidence & {
          readonly identifierId: string;
          readonly partyId: string;
        }
      >(
        `/api/v1/parties/${party.partyId}/identifiers`,
        {
          effectiveFrom: textValue(data, "effectiveFrom") || null,
          effectiveTo: textValue(data, "effectiveTo") || null,
          identifierType,
          jurisdiction,
          reason: textValue(data, "reason"),
          value,
        },
        {
          ...previewEvidence(nextVersion),
          identifierId: nextIdentifierId,
          partyId: party.partyId,
        },
        refresh,
      );
      if (result && runtime.previewMode) {
        setParty((current) =>
          current
            ? {
                ...current,
                identifiers: [
                  ...current.identifiers.filter(
                    (item) => item.identifierType !== identifierType,
                  ),
                  {
                    identifierId: result.identifierId,
                    identifierType,
                    jurisdiction,
                    maskedValue: `••••${value.slice(-4)}`,
                  },
                ],
                version: result.aggregateVersion,
              }
            : current,
        );
        form.reset();
      }
      return;
    }

    if (action === "reveal-identifier" && identifierId) {
      const result = await command<{
        readonly auditEventId: string;
        readonly identifierId: string;
        readonly partyId: string;
        readonly value: string;
      }>(
        `/api/v1/parties/${party.partyId}/identifiers/${identifierId}/reveal`,
        { reason: textValue(data, "reason") },
        {
          auditEventId: crypto.randomUUID(),
          identifierId,
          partyId: party.partyId,
          value: "PREVIEW-IDENTIFIER-0141",
        },
        refresh,
      );
      if (result) {
        setRevealedIdentifier({
          identifierId: result.identifierId,
          value: result.value,
        });
      }
      return;
    }

    if (action === "archive") {
      const result = await command<
        M3CommandEvidence & { readonly partyId: string }
      >(
        `/api/v1/parties/${party.partyId}`,
        {
          expectedVersion: party.version,
          reason: textValue(data, "reason"),
        },
        {
          ...previewEvidence(nextVersion),
          partyId: party.partyId,
        },
        refresh,
        "DELETE",
      );
      if (result && runtime.previewMode) {
        setParty((current) =>
          current
            ? {
                ...current,
                status: "archived",
                version: result.aggregateVersion,
              }
            : current,
        );
      }
    }
  }

  const filteredLeads = useMemo(() => {
    const query = search.trim().toLocaleLowerCase(locale);
    return query
      ? leads.filter((item) =>
          `${item.summary} ${item.sourceKey}`
            .toLocaleLowerCase(locale)
            .includes(query),
        )
      : leads;
  }, [leads, locale, search]);

  const filteredParties = useMemo(() => {
    const query = search.trim().toLocaleLowerCase(locale);
    return query
      ? parties.filter((item) =>
          item.displayName.toLocaleLowerCase(locale).includes(query),
        )
      : parties;
  }, [locale, parties, search]);

  if (loading) {
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
  }

  if (view === "lead-new") {
    return (
      <LeadCreate
        copy={copy}
        onSubmit={async (event) => {
          event.preventDefault();
          const data = new FormData(event.currentTarget);
          const result = await command<{ readonly leadId: string }>(
            "/api/v1/leads",
            {
              assigneeMembershipId:
                textValue(data, "assigneeMembershipId") || null,
              interestedInventoryUnitId: null,
              nextActionAt: isoOrNull(data.get("nextActionAt")),
              prospectPartyId: textValue(data, "prospectPartyId") || null,
              sourceKey: textValue(data, "sourceKey"),
              summary: textValue(data, "summary"),
            },
            { leadId: ids.leadA },
            (created) => refreshLeadDetail(created.leadId),
          );
          if (result) {
            router.push(
              withPreview(
                `/people/leads/${result.leadId}`,
                runtime.previewMode,
              ),
            );
          }
        }}
        previewMode={runtime.previewMode}
        runtime={runtime}
        status={
          <M3InlineStatus
            copy={copy.common}
            error={error}
            saved={saved}
            saving={saving}
          />
        }
      />
    );
  }

  if (view === "lead-detail") {
    return (
      <LeadDetail
        activities={activities}
        copy={copy}
        lead={lead}
        locale={locale}
        onActivity={async (event) => {
          event.preventDefault();
          if (!lead) return;
          const data = new FormData(event.currentTarget);
          const subject = textValue(data, "subject");
          const body = textValue(data, "body");
          const optimisticActivity: ActivityRow = {
            activityId: crypto.randomUUID(),
            activityType: "note",
            actorUserId: ids.membership,
            body: body || null,
            dealId: null,
            direction: "internal",
            leadId: lead.leadId,
            occurredAt: new Date().toISOString(),
            partyId: lead.prospectPartyId,
            subject,
          };
          const result = await command<{ readonly activityId: string }>(
            "/api/v1/activities",
            {
              activityType: "note",
              body: body || null,
              channelKey: null,
              dealId: null,
              direction: "internal",
              leadId: lead.leadId,
              occurredAt: new Date().toISOString(),
              partyId: lead.prospectPartyId,
              providerReference: null,
              subject,
            },
            { activityId: optimisticActivity.activityId },
            () => refreshLeadDetail(lead.leadId),
          );
          if (result) {
            if (runtime.previewMode) {
              setActivities((current) => [optimisticActivity, ...current]);
            }
            event.currentTarget.reset();
          }
        }}
        onConvert={async (event) => {
          event.preventDefault();
          if (!lead) return;
          const data = new FormData(event.currentTarget);
          const result = await command<{ readonly dealId: string }>(
            `/api/v1/leads/${lead.leadId}/convert`,
            {
              currencyCode: textValue(data, "currencyCode"),
              dealTypeKey: textValue(data, "dealTypeKey"),
              expectedVersion: lead.version,
              legalEntityId: textValue(data, "legalEntityId") || null,
              locationId: textValue(data, "locationId"),
              ownerMembershipId: textValue(data, "ownerMembershipId") || null,
            },
            { dealId: ids.deal },
            async (created) => {
              await requestM3Json({
                context: runtime.apiContext,
                path: `/api/v1/deals/${created.dealId}`,
              });
            },
          );
          if (result) {
            router.push(
              withPreview(`/deals/${result.dealId}`, runtime.previewMode),
            );
          }
        }}
        onTransition={async (event) => {
          event.preventDefault();
          if (!lead) return;
          const data = new FormData(event.currentTarget);
          const reason = textValue(data, "reason");
          const transition =
            lead.availableTransitions?.find(
              (item) => item.transitionKey === transitionTarget,
            ) ?? lead.availableTransitions?.[0];
          if (!transition) return;
          if (transition.reasonRequired && !reason) {
            setError(copy.crm.reasonRequired);
            return;
          }
          const result = await command<{
            readonly aggregateVersion: number;
            readonly leadId: string;
            readonly stateKey: string;
          }>(
            `/api/v1/leads/${lead.leadId}/transition`,
            {
              expectedVersion: lead.version,
              reason: reason || null,
              transitionKey: transition.transitionKey,
            },
            {
              aggregateVersion: lead.version + 1,
              leadId: lead.leadId,
              stateKey: transition.toStateKey,
            },
            () => refreshLeadDetail(lead.leadId),
          );
          if (result && runtime.previewMode) {
            setLead({
              ...lead,
              conversionEligible: transition.conversionEligibleAfter ?? false,
              lostReason: reason || null,
              stateKey: transition.toStateKey,
              version: result.aggregateVersion,
            });
          }
        }}
        previewMode={runtime.previewMode}
        runtime={runtime}
        status={
          <M3InlineStatus
            copy={copy.common}
            error={error}
            saved={saved}
            saving={saving}
          />
        }
        transitionTarget={transitionTarget}
        onTransitionTarget={setTransitionTarget}
      />
    );
  }

  if (view === "party-detail") {
    return (
      <PartyDetail
        copy={copy}
        onMutation={handlePartyMutation}
        party={party}
        previewMode={runtime.previewMode}
        revealedIdentifier={revealedIdentifier}
        runtime={runtime}
        status={
          <M3InlineStatus
            copy={copy.common}
            error={error}
            saved={saved}
            saving={saving}
          />
        }
      />
    );
  }

  if (view === "tasks") {
    return (
      <TaskWorkbench
        copy={copy}
        locale={locale}
        onCancel={async (event, item) => {
          event.preventDefault();
          const data = new FormData(event.currentTarget);
          const result = await command<{
            readonly taskId: string;
            readonly taskState: TaskRow["state"];
          }>(
            `/api/v1/tasks/${item.taskId}/cancel`,
            {
              expectedVersion: item.version,
              reason: textValue(data, "reason"),
            },
            { taskId: item.taskId, taskState: "cancelled" },
            () => refreshTasks(),
          );
          if (result && runtime.previewMode) {
            setTasks((current) =>
              current.map((row) =>
                row.taskId === item.taskId
                  ? {
                      ...row,
                      state: result.taskState,
                      version: row.version + 1,
                    }
                  : row,
              ),
            );
          }
        }}
        onComplete={async (item) => {
          const result = await command<{
            readonly taskId: string;
            readonly taskState: TaskRow["state"];
          }>(
            `/api/v1/tasks/${item.taskId}/complete`,
            { expectedVersion: item.version },
            { taskId: item.taskId, taskState: "completed" },
            () => refreshTasks(),
          );
          if (result && runtime.previewMode) {
            setTasks((current) =>
              current.map((row) =>
                row.taskId === item.taskId
                  ? {
                      ...row,
                      state: result.taskState,
                      version: row.version + 1,
                    }
                  : row,
              ),
            );
          }
        }}
        onCreate={async (event) => {
          event.preventDefault();
          const form = event.currentTarget;
          const data = new FormData(form);
          const title = textValue(data, "title");
          const dealId = textValue(data, "dealId") || null;
          const leadId = textValue(data, "leadId") || null;
          const partyId = textValue(data, "partyId") || null;
          if (!dealId && !leadId && !partyId) {
            setError(copy.crm.relationRequired);
            return;
          }
          const optimisticTask: TaskRow = {
            assigneeMembershipId: textValue(data, "assigneeMembershipId"),
            dealId,
            dueAt: isoOrNull(data.get("dueAt")) ?? new Date().toISOString(),
            leadId,
            partyId,
            priority: "normal",
            reminderAt: null,
            state: "open",
            taskId: crypto.randomUUID(),
            title,
            version: 1,
          };
          const result = await command<{
            readonly taskId: string;
            readonly taskState: TaskRow["state"];
          }>(
            "/api/v1/tasks",
            {
              assigneeMembershipId: textValue(data, "assigneeMembershipId"),
              dealId,
              description: textValue(data, "description") || null,
              dueAt: isoOrNull(data.get("dueAt")),
              leadId,
              partyId,
              priority: "normal",
              reminderAt: null,
              title,
            },
            { taskId: optimisticTask.taskId, taskState: "open" },
            () => refreshTasks(),
          );
          if (result) {
            if (runtime.previewMode) {
              setTasks((current) => [optimisticTask, ...current]);
            }
            form.reset();
          }
        }}
        runtime={runtime}
        status={
          <M3InlineStatus
            copy={copy.common}
            error={error}
            saved={saved}
            saving={saving}
          />
        }
        tasks={tasks}
      />
    );
  }

  if (view === "appointments") {
    return (
      <AppointmentWorkbench
        appointments={appointments}
        copy={copy}
        locale={locale}
        onCreate={async (event) => {
          event.preventDefault();
          const form = event.currentTarget;
          const data = new FormData(form);
          const title = textValue(data, "title");
          const dealId = textValue(data, "dealId") || null;
          const leadId = textValue(data, "leadId") || null;
          if (!dealId && !leadId) {
            setError(copy.crm.relationRequired);
            return;
          }
          const optimisticAppointment: AppointmentRow = {
            appointmentId: crypto.randomUUID(),
            dealId,
            endsAt: isoOrNull(data.get("endsAt")) ?? new Date().toISOString(),
            leadId,
            locationId: null,
            startsAt:
              isoOrNull(data.get("startsAt")) ?? new Date().toISOString(),
            status: "scheduled",
            timezone: textValue(data, "timezone"),
            title,
            version: 1,
          };
          const result = await command<{
            readonly appointmentId: string;
            readonly appointmentStatus: AppointmentRow["status"];
          }>(
            "/api/v1/appointments",
            {
              attendeePartyIds: [],
              dealId,
              endsAt: isoOrNull(data.get("endsAt")),
              leadId,
              locationId: null,
              notes: textValue(data, "notes") || null,
              remoteDetails: null,
              startsAt: isoOrNull(data.get("startsAt")),
              timezone: textValue(data, "timezone"),
              title,
            },
            {
              appointmentId: optimisticAppointment.appointmentId,
              appointmentStatus: "scheduled",
            },
            () => refreshAppointments(),
          );
          if (result) {
            if (runtime.previewMode) {
              setAppointments((current) => [optimisticAppointment, ...current]);
            }
            form.reset();
          }
        }}
        onTransition={async (event, appointment) => {
          event.preventDefault();
          const data = new FormData(event.currentTarget);
          const targetStatus = textValue(data, "targetStatus") as
            "cancelled" | "completed" | "no_show";
          const result = await command<{
            readonly appointmentId: string;
            readonly appointmentStatus: AppointmentRow["status"];
          }>(
            `/api/v1/appointments/${appointment.appointmentId}/transition`,
            {
              expectedVersion: appointment.version,
              outcome: textValue(data, "outcome") || null,
              reason: textValue(data, "reason") || null,
              targetStatus,
            },
            {
              appointmentId: appointment.appointmentId,
              appointmentStatus: targetStatus,
            },
            () => refreshAppointments(),
          );
          if (result && runtime.previewMode) {
            setAppointments((current) =>
              current.map((row) =>
                row.appointmentId === appointment.appointmentId
                  ? {
                      ...row,
                      status: result.appointmentStatus,
                      version: row.version + 1,
                    }
                  : row,
              ),
            );
          }
        }}
        runtime={runtime}
        status={
          <M3InlineStatus
            copy={copy.common}
            error={error}
            saved={saved}
            saving={saving}
          />
        }
      />
    );
  }

  const list = view === "parties" ? filteredParties : filteredLeads;
  return (
    <WorkbenchSection
      action={
        view === "leads" ? (
          <Link
            className={m3PrimaryButtonClass}
            href={withPreview("/people/leads/new", runtime.previewMode)}
          >
            <Plus aria-hidden="true" size={18} />
            {copy.crm.newLead}
          </Link>
        ) : undefined
      }
      description={
        view === "parties" ? copy.crm.partyDetails : copy.crm.emptyDescription
      }
      title={
        view === "parties"
          ? copy.crm.partyCount(list.length)
          : copy.crm.leadCount(list.length)
      }
    >
      <div className="border-y border-[var(--line)] bg-[var(--paper)] px-4 py-3 sm:px-6 lg:px-8">
        <label className="sr-only" htmlFor="m3-crm-search">
          {copy.crm.searchLabel}
        </label>
        <Input
          className={`${m3FieldClass} max-w-xl`}
          id="m3-crm-search"
          onChange={(event) => setSearch(event.target.value)}
          placeholder={copy.crm.searchLabel}
          type="search"
          value={search}
        />
      </div>
      {error ? (
        <p
          className="m-0 px-4 py-4 text-sm font-bold text-[var(--rust)]"
          role="alert"
        >
          {error}
        </p>
      ) : null}
      {view === "parties" ? (
        <PartyCreateForm
          copy={copy}
          onSubmit={async (event) => {
            event.preventDefault();
            const form = event.currentTarget;
            const data = new FormData(form);
            const partyType = textValue(data, "partyType") as
              "organization" | "person";
            const displayName = textValue(data, "displayName");
            const preferredLocale = textValue(data, "preferredLocale") as
              "en" | "fr";
            const partyId = crypto.randomUUID();
            const result = await command<
              M3CommandEvidence & { readonly partyId: string }
            >(
              "/api/v1/parties",
              partyType === "person"
                ? {
                    displayName,
                    partyType,
                    person: {
                      birthDate: textValue(data, "birthDate") || null,
                      familyName: textValue(data, "familyName"),
                      givenName: textValue(data, "givenName"),
                      preferredName: textValue(data, "preferredName") || null,
                    },
                    preferredLocale,
                  }
                : {
                    displayName,
                    organization: {
                      legalName: textValue(data, "legalName"),
                      registrationName:
                        textValue(data, "registrationName") || null,
                    },
                    partyType,
                    preferredLocale,
                  },
              {
                ...previewEvidence(1),
                partyId,
              },
              () => refreshParties(),
            );
            if (result) {
              if (runtime.previewMode) {
                setParties((current) => [
                  {
                    displayName,
                    partyId: result.partyId,
                    partyType,
                    preferredLocale,
                    status: "active",
                    version: result.aggregateVersion,
                  },
                  ...current,
                ]);
              }
              form.reset();
            }
          }}
          runtime={runtime}
          status={
            <M3InlineStatus
              copy={copy.common}
              error={error}
              saved={saved}
              saving={saving}
            />
          }
        />
      ) : null}
      {list.length === 0 ? (
        <div className="px-4 py-14 sm:px-6 lg:px-8">
          <h3 className="m-0 text-xl">{copy.crm.emptyHeading}</h3>
          <p className="mb-0 mt-2 text-sm text-muted-foreground">
            {copy.crm.emptyDescription}
          </p>
        </div>
      ) : view === "parties" ? (
        <div>
          {filteredParties.map((item) => (
            <PartyListRow
              copy={copy}
              item={item}
              key={item.partyId}
              previewMode={runtime.previewMode}
            />
          ))}
        </div>
      ) : (
        <div>
          {filteredLeads.map((item) => (
            <LeadListRow
              copy={copy}
              item={item}
              key={item.leadId}
              locale={locale}
              previewMode={runtime.previewMode}
            />
          ))}
        </div>
      )}
    </WorkbenchSection>
  );
}

function LeadListRow({
  copy,
  item,
  locale,
  previewMode,
}: {
  readonly copy: M3Messages;
  readonly item: LeadRow;
  readonly locale: Locale;
  readonly previewMode: boolean;
}) {
  return (
    <article className="grid gap-4 border-b border-[var(--line)] px-4 py-5 last:border-b-0 sm:grid-cols-[minmax(0,1fr)_minmax(12rem,0.5fr)_auto] sm:items-center sm:px-6 lg:px-8">
      <div className="min-w-0">
        <Status label={copy.crm.stateLabels[item.stateKey] ?? item.stateKey} />
        <h3 className="mb-0 mt-2 text-base font-bold leading-6">
          {item.summary}
        </h3>
        <p className="mb-0 mt-1 break-words text-xs text-muted-foreground">
          {item.sourceKey}
        </p>
      </div>
      <div>
        <p className="m-0 text-xs font-bold uppercase tracking-[0.08em] text-muted-foreground">
          {copy.crm.nextAction}
        </p>
        <p className="mb-0 mt-1 text-sm">
          {item.nextActionAt ? dateTime(item.nextActionAt, locale) : "—"}
        </p>
      </div>
      <Link
        aria-label={`${copy.common.view}: ${item.summary}`}
        className={m3LinkButtonClass}
        href={withPreview(`/people/leads/${item.leadId}`, previewMode)}
      >
        {copy.common.view}
        <ArrowRight aria-hidden="true" size={16} />
      </Link>
    </article>
  );
}

function PartyCreateForm({
  copy,
  onSubmit,
  runtime,
  status,
}: {
  readonly copy: M3Messages;
  readonly onSubmit: (event: FormEvent<HTMLFormElement>) => void;
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
}) {
  const [partyType, setPartyType] = useState<"organization" | "person">(
    "person",
  );
  return (
    <details className="border-b border-[var(--line)] bg-[var(--paper)]">
      <summary className="cursor-pointer px-4 py-4 text-sm font-bold sm:px-6 lg:px-8">
        {copy.crm.newParty}
      </summary>
      <form
        className="grid gap-4 px-4 pb-6 sm:grid-cols-2 sm:px-6 lg:px-8"
        onSubmit={onSubmit}
      >
        <Field label={copy.crm.partyType} required>
          <NativeSelect
            className={m3FieldClass}
            name="partyType"
            onChange={(event) =>
              setPartyType(event.target.value as "organization" | "person")
            }
            value={partyType}
          >
            <option value="person">{copy.crm.person}</option>
            <option value="organization">{copy.crm.organization}</option>
          </NativeSelect>
        </Field>
        <Field label={copy.crm.preferredLocale} required>
          <NativeSelect
            className={m3FieldClass}
            defaultValue="en"
            name="preferredLocale"
          >
            <option value="en">{copy.common.localeNames.en}</option>
            <option value="fr">{copy.common.localeNames.fr}</option>
          </NativeSelect>
        </Field>
        <Field label={copy.crm.displayName} required>
          <Input className={m3FieldClass} name="displayName" required />
        </Field>
        {partyType === "person" ? (
          <>
            <Field label={copy.crm.givenName} required>
              <Input className={m3FieldClass} name="givenName" required />
            </Field>
            <Field label={copy.crm.familyName} required>
              <Input className={m3FieldClass} name="familyName" required />
            </Field>
            <Field label={copy.crm.preferredName}>
              <Input className={m3FieldClass} name="preferredName" />
            </Field>
            <Field label={copy.crm.birthDate}>
              <Input className={m3FieldClass} name="birthDate" type="date" />
            </Field>
          </>
        ) : (
          <>
            <Field label={copy.crm.legalName} required>
              <Input className={m3FieldClass} name="legalName" required />
            </Field>
            <Field label={copy.crm.registrationName}>
              <Input className={m3FieldClass} name="registrationName" />
            </Field>
          </>
        )}
        <div className="flex flex-wrap items-center gap-3 sm:col-span-2">
          <Button
            className={m3PrimaryButtonClass}
            disabled={!runtime.canWrite}
            type="submit"
          >
            <Plus aria-hidden="true" size={16} />
            {copy.common.create}
          </Button>
          {status}
        </div>
      </form>
    </details>
  );
}

function PartyListRow({
  copy,
  item,
  previewMode,
}: {
  readonly copy: M3Messages;
  readonly item: PartyListRow;
  readonly previewMode: boolean;
}) {
  return (
    <article className="grid gap-4 border-b border-[var(--line)] px-4 py-5 last:border-b-0 sm:grid-cols-[minmax(0,1fr)_minmax(10rem,0.35fr)_auto] sm:items-center sm:px-6 lg:px-8">
      <div className="min-w-0">
        <h3 className="m-0 text-base font-bold">{item.displayName}</h3>
        <p className="mb-0 mt-1 text-sm text-muted-foreground">
          {item.partyType === "person"
            ? copy.crm.person
            : copy.crm.organization}
        </p>
      </div>
      <div>
        <Status
          label={copy.crm.partyStatusLabels[item.status] ?? item.status}
        />
        <p className="mb-0 mt-2 text-xs text-muted-foreground">
          {item.preferredLocale.toUpperCase()}
        </p>
      </div>
      <Link
        aria-label={`${copy.common.view}: ${item.displayName}`}
        className={m3LinkButtonClass}
        href={withPreview(`/people/parties/${item.partyId}`, previewMode)}
      >
        {copy.common.view}
        <ArrowRight aria-hidden="true" size={16} />
      </Link>
    </article>
  );
}

function LeadCreate({
  copy,
  onSubmit,
  previewMode,
  runtime,
  status,
}: {
  readonly copy: M3Messages;
  readonly onSubmit: (event: FormEvent<HTMLFormElement>) => void;
  readonly previewMode: boolean;
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
}) {
  return (
    <WorkbenchSection
      description={copy.crm.emptyDescription}
      title={copy.crm.newLead}
    >
      <form
        className="grid max-w-3xl gap-5 px-4 py-6 sm:grid-cols-2 sm:px-6 lg:px-8"
        onSubmit={onSubmit}
      >
        <div className="sm:col-span-2">
          <Link
            className={m3LinkButtonClass}
            href={withPreview("/people", previewMode)}
          >
            <ArrowLeft aria-hidden="true" size={16} />
            {copy.common.back}
          </Link>
        </div>
        <div className="sm:col-span-2">
          <Field label={copy.crm.leadSummary} required>
            <Textarea className={m3TextAreaClass} name="summary" required />
          </Field>
        </div>
        <Field label={copy.crm.source} required>
          <Input
            className={m3FieldClass}
            defaultValue="walk_in"
            name="sourceKey"
            required
          />
        </Field>
        <Field label={copy.crm.nextActionAt}>
          <Input
            className={m3FieldClass}
            name="nextActionAt"
            type="datetime-local"
          />
        </Field>
        <Field label={copy.crm.prospectPartyId}>
          <Input
            className={m3FieldClass}
            defaultValue={runtime.previewMode ? ids.partyA : ""}
            name="prospectPartyId"
          />
        </Field>
        <Field label={copy.crm.assigneeMembershipId}>
          <Input
            className={m3FieldClass}
            defaultValue={runtime.previewMode ? ids.membership : ""}
            name="assigneeMembershipId"
          />
        </Field>
        <div className="flex flex-wrap items-center gap-3 sm:col-span-2">
          <Button
            className={m3PrimaryButtonClass}
            disabled={!runtime.canWrite}
            type="submit"
          >
            <Plus aria-hidden="true" size={18} />
            {copy.common.create}
          </Button>
          {status}
        </div>
      </form>
    </WorkbenchSection>
  );
}

function LeadDetail({
  activities,
  copy,
  lead,
  locale,
  onActivity,
  onConvert,
  onTransition,
  onTransitionTarget,
  previewMode,
  runtime,
  status,
  transitionTarget,
}: {
  readonly activities: readonly ActivityRow[];
  readonly copy: M3Messages;
  readonly lead: LeadRow | null;
  readonly locale: Locale;
  readonly onActivity: (event: FormEvent<HTMLFormElement>) => void;
  readonly onConvert: (event: FormEvent<HTMLFormElement>) => void;
  readonly onTransition: (event: FormEvent<HTMLFormElement>) => void;
  readonly onTransitionTarget: (value: string) => void;
  readonly previewMode: boolean;
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
  readonly transitionTarget: string;
}) {
  if (!lead) return <p className="px-4 py-12">{copy.crm.emptyHeading}</p>;
  const selectedTransition =
    lead.availableTransitions?.find(
      (item) => item.transitionKey === transitionTarget,
    ) ?? lead.availableTransitions?.[0];
  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--line)] px-4 py-4 sm:px-6 lg:px-8">
        <Link
          className={m3LinkButtonClass}
          href={withPreview("/people", previewMode)}
        >
          <ArrowLeft aria-hidden="true" size={16} />
          {copy.common.back}
        </Link>
        {status}
      </div>
      <WorkbenchSection
        title={lead.summary}
        description={copy.crm.convertDescription}
      >
        <dl className="grid border-y border-[var(--line)] sm:grid-cols-3">
          {[
            [
              copy.common.status,
              copy.crm.stateLabels[lead.stateKey] ?? lead.stateKey,
            ],
            [
              copy.crm.nextAction,
              lead.nextActionAt ? dateTime(lead.nextActionAt, locale) : "—",
            ],
            [copy.crm.source, lead.sourceKey],
          ].map(([term, value]) => (
            <div
              className="border-b border-[var(--line)] px-4 py-4 last:border-b-0 sm:border-b-0 sm:border-r sm:px-6 sm:last:border-r-0"
              key={term}
            >
              <dt className="text-xs font-bold uppercase tracking-[0.08em] text-muted-foreground">
                {term}
              </dt>
              <dd className="mb-0 ml-0 mt-2 break-words text-sm font-semibold">
                {value}
              </dd>
            </div>
          ))}
        </dl>
      </WorkbenchSection>
      <WorkbenchSection
        description={copy.crm.reasonRequired}
        title={copy.crm.transition}
      >
        <form
          className="grid gap-4 px-4 pb-6 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto] sm:items-end sm:px-6 lg:px-8"
          onSubmit={onTransition}
        >
          <Field label={copy.crm.transitionTarget} required>
            <NativeSelect
              className={m3FieldClass}
              onChange={(event) => onTransitionTarget(event.target.value)}
              value={selectedTransition?.transitionKey ?? ""}
            >
              {(lead.availableTransitions ?? []).map((transition) => (
                <option
                  key={transition.transitionKey}
                  value={transition.transitionKey}
                >
                  {transition.labels[locale] ?? transition.toStateKey}
                </option>
              ))}
            </NativeSelect>
          </Field>
          <Field
            label={copy.crm.lostReason}
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
            disabled={!runtime.canWrite}
            type="submit"
          >
            {copy.crm.transition}
            <ArrowRight aria-hidden="true" size={16} />
          </Button>
        </form>
      </WorkbenchSection>
      <WorkbenchSection
        description={copy.crm.convertDescription}
        title={copy.crm.convert}
      >
        <form
          className="grid gap-4 px-4 pb-6 sm:grid-cols-2 sm:px-6 lg:grid-cols-3 lg:px-8"
          onSubmit={onConvert}
        >
          <Field label={copy.crm.dealTypeKey} required>
            <Input
              className={m3FieldClass}
              defaultValue="retail_sale"
              name="dealTypeKey"
              required
            />
          </Field>
          <Field label={copy.crm.currencyCode} required>
            <Input
              className={m3FieldClass}
              defaultValue="CAD"
              maxLength={3}
              name="currencyCode"
              required
            />
          </Field>
          <Field label={copy.crm.locationId} required>
            <Input
              className={m3FieldClass}
              defaultValue={runtime.previewMode ? ids.location : ""}
              name="locationId"
              required
            />
          </Field>
          <Field label={copy.crm.ownerMembershipId}>
            <Input
              className={m3FieldClass}
              defaultValue={runtime.previewMode ? ids.membership : ""}
              name="ownerMembershipId"
            />
          </Field>
          <Field label={copy.crm.legalEntityId}>
            <Input className={m3FieldClass} name="legalEntityId" />
          </Field>
          <Button
            className={`${m3PrimaryButtonClass} self-end`}
            disabled={!runtime.canWrite || !lead.conversionEligible}
            type="submit"
          >
            {copy.crm.convert}
            <ArrowRight aria-hidden="true" size={16} />
          </Button>
        </form>
      </WorkbenchSection>
      <WorkbenchSection
        description={activities.length === 0 ? copy.crm.noTimeline : undefined}
        title={copy.crm.timeline}
      >
        <form
          className="grid gap-4 border-y border-[var(--line)] bg-[var(--paper)] px-4 py-5 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={onActivity}
        >
          <Field label={copy.crm.activitySubject} required>
            <Input className={m3FieldClass} name="subject" required />
          </Field>
          <Field label={copy.crm.activityBody}>
            <Input className={m3FieldClass} name="body" />
          </Field>
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
            disabled={!runtime.canWrite}
            type="submit"
          >
            <Plus aria-hidden="true" size={16} />
            {copy.crm.addActivity}
          </Button>
        </form>
        <ol className="m-0 list-none p-0">
          {activities.map((activity) => (
            <li
              className="grid gap-1 border-b border-[var(--line)] px-4 py-5 last:border-b-0 sm:grid-cols-[12rem_1fr] sm:px-6 lg:px-8"
              key={activity.activityId}
            >
              <time className="text-xs font-bold uppercase tracking-[0.08em] text-muted-foreground">
                {dateTime(activity.occurredAt, locale)}
              </time>
              <div>
                <h3 className="m-0 text-sm font-bold">{activity.subject}</h3>
                {activity.body ? (
                  <p className="mb-0 mt-1 text-sm leading-6 text-muted-foreground">
                    {activity.body}
                  </p>
                ) : null}
              </div>
            </li>
          ))}
        </ol>
      </WorkbenchSection>
    </div>
  );
}

function PartyDetail({
  copy,
  onMutation,
  party,
  previewMode,
  revealedIdentifier,
  runtime,
  status,
}: {
  readonly copy: M3Messages;
  readonly onMutation: (
    action: PartyMutationAction,
    event: FormEvent<HTMLFormElement>,
    identifierId?: string,
  ) => void;
  readonly party: PartyDetailRow | null;
  readonly previewMode: boolean;
  readonly revealedIdentifier: Readonly<{
    identifierId: string;
    value: string;
  }> | null;
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
}) {
  if (!party) return <p className="px-4 py-12">{copy.crm.emptyHeading}</p>;
  return (
    <div>
      <div className="border-b border-[var(--line)] px-4 py-4 sm:px-6 lg:px-8">
        <Link
          className={m3LinkButtonClass}
          href={withPreview("/people/parties", previewMode)}
        >
          <ArrowLeft aria-hidden="true" size={16} />
          {copy.common.back}
        </Link>
      </div>
      <WorkbenchSection
        description={copy.crm.partyDetails}
        title={party.displayName}
      >
        <dl className="grid border-y border-[var(--line)] sm:grid-cols-3">
          {[
            [copy.common.status, party.status],
            [copy.common.localeLabel, party.preferredLocale.toUpperCase()],
            [copy.common.details, party.partyId],
          ].map(([term, value]) => (
            <div
              className="min-w-0 border-b border-[var(--line)] px-4 py-4 last:border-b-0 sm:border-b-0 sm:border-r sm:px-6 sm:last:border-r-0"
              key={term}
            >
              <dt className="text-xs font-bold uppercase tracking-[0.08em] text-muted-foreground">
                {term}
              </dt>
              <dd className="mb-0 ml-0 mt-2 break-all text-sm font-semibold">
                {value}
              </dd>
            </div>
          ))}
        </dl>
      </WorkbenchSection>
      <WorkbenchSection title={copy.crm.partyProfile}>
        <form
          className="grid gap-4 px-4 pb-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={(event) => onMutation("update", event)}
        >
          <Field label={copy.crm.displayName} required>
            <Input
              className={m3FieldClass}
              defaultValue={party.displayName}
              name="displayName"
              required
            />
          </Field>
          <Field label={copy.crm.preferredLocale} required>
            <NativeSelect
              className={m3FieldClass}
              defaultValue={party.preferredLocale}
              name="preferredLocale"
            >
              <option value="en">{copy.common.localeNames.en}</option>
              <option value="fr">{copy.common.localeNames.fr}</option>
            </NativeSelect>
          </Field>
          {party.partyType === "person" ? (
            <>
              <Field label={copy.crm.givenName} required>
                <Input
                  className={m3FieldClass}
                  defaultValue={party.profile.givenName ?? ""}
                  name="givenName"
                  required
                />
              </Field>
              <Field label={copy.crm.familyName} required>
                <Input
                  className={m3FieldClass}
                  defaultValue={party.profile.familyName ?? ""}
                  name="familyName"
                  required
                />
              </Field>
              <Field label={copy.crm.preferredName}>
                <Input
                  className={m3FieldClass}
                  defaultValue={party.profile.preferredName ?? ""}
                  name="preferredName"
                />
              </Field>
              <Field label={copy.crm.birthDate}>
                <Input
                  className={m3FieldClass}
                  defaultValue={party.profile.birthDate ?? ""}
                  name="birthDate"
                  type="date"
                />
              </Field>
            </>
          ) : (
            <>
              <Field label={copy.crm.legalName} required>
                <Input
                  className={m3FieldClass}
                  defaultValue={party.profile.legalName ?? ""}
                  name="legalName"
                  required
                />
              </Field>
              <Field label={copy.crm.registrationName}>
                <Input
                  className={m3FieldClass}
                  defaultValue={party.profile.registrationName ?? ""}
                  name="registrationName"
                />
              </Field>
            </>
          )}
          <div className="flex flex-wrap items-center gap-3 sm:col-span-2">
            <Button
              className={m3PrimaryButtonClass}
              disabled={!runtime.canWrite || party.status === "archived"}
              type="submit"
            >
              {copy.crm.updateProfile}
            </Button>
            {status}
          </div>
        </form>
      </WorkbenchSection>
      <WorkbenchSection title={copy.crm.contactDetails}>
        {party.contacts.length === 0 ? (
          <p className="px-4 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.crm.noContacts}
          </p>
        ) : (
          <div>
            {party.contacts.map((contact) => (
              <div
                className="grid gap-2 border-b border-[var(--line)] px-4 py-4 last:border-b-0 sm:grid-cols-[9rem_1fr] sm:px-6 lg:px-8"
                key={contact.contactId}
              >
                <span className="text-xs font-bold uppercase tracking-[0.08em] text-muted-foreground">
                  {copy.crm.contactTypeLabels[contact.contactType] ??
                    contact.contactType}
                </span>
                <span className="break-words text-sm font-semibold">
                  {contact.value}
                </span>
              </div>
            ))}
          </div>
        )}
        <form
          className="grid gap-4 border-t border-[var(--line)] px-4 py-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={(event) => onMutation("add-contact", event)}
        >
          <Field label={copy.crm.contactDetails} required>
            <NativeSelect className={m3FieldClass} name="contactType">
              <option value="email">{copy.crm.contactTypeLabels.email}</option>
              <option value="phone">{copy.crm.contactTypeLabels.phone}</option>
            </NativeSelect>
          </Field>
          <Field label={copy.crm.identifierValue} required>
            <Input className={m3FieldClass} name="value" required />
          </Field>
          <Field label={copy.crm.consentStatus} required>
            <NativeSelect
              className={m3FieldClass}
              defaultValue="unknown"
              name="consentStatus"
            >
              <option value="unknown">unknown</option>
              <option value="granted">granted</option>
              <option value="denied">denied</option>
              <option value="withdrawn">withdrawn</option>
            </NativeSelect>
          </Field>
          <Field label={copy.crm.consentSource}>
            <Input className={m3FieldClass} name="consentSource" />
          </Field>
          <div className="flex flex-wrap gap-4 sm:col-span-2">
            <BooleanField label={copy.crm.isPrimary} name="isPrimary" />
            <BooleanField label={copy.crm.isPreferred} name="isPreferred" />
            <BooleanField label={copy.crm.doNotContact} name="doNotContact" />
          </div>
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
            disabled={!runtime.canWrite || party.status === "archived"}
            type="submit"
          >
            <Plus aria-hidden="true" size={16} />
            {copy.crm.addContact}
          </Button>
        </form>
      </WorkbenchSection>
      <WorkbenchSection title={copy.crm.addresses}>
        {party.addresses.length === 0 ? (
          <p className="px-4 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.crm.noAddresses}
          </p>
        ) : (
          <div>
            {party.addresses.map((address) => (
              <address
                className="border-b border-[var(--line)] px-4 py-4 text-sm not-italic sm:px-6 lg:px-8"
                key={address.addressId}
              >
                <strong>{address.addressType}</strong>
                <br />
                {address.line1}
                {address.line2 ? `, ${address.line2}` : ""}
                <br />
                {address.locality}, {address.region} {address.postalCode} ·{" "}
                {address.countryCode}
              </address>
            ))}
          </div>
        )}
        <form
          className="grid gap-4 border-t border-[var(--line)] px-4 py-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={(event) => onMutation("add-address", event)}
        >
          <Field label={copy.crm.addressType} required>
            <Input
              className={m3FieldClass}
              defaultValue="home"
              name="addressType"
              required
            />
          </Field>
          <Field label={copy.crm.countryCode} required>
            <Input
              className={m3FieldClass}
              defaultValue="CA"
              maxLength={2}
              name="countryCode"
              required
            />
          </Field>
          <Field label={copy.crm.line1} required>
            <Input className={m3FieldClass} name="line1" required />
          </Field>
          <Field label={copy.crm.line2}>
            <Input className={m3FieldClass} name="line2" />
          </Field>
          <Field label={copy.crm.locality} required>
            <Input className={m3FieldClass} name="locality" required />
          </Field>
          <Field label={copy.crm.region} required>
            <Input className={m3FieldClass} name="region" required />
          </Field>
          <Field label={copy.crm.postalCode} required>
            <Input className={m3FieldClass} name="postalCode" required />
          </Field>
          <BooleanField label={copy.crm.isPrimary} name="isPrimary" />
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
            disabled={!runtime.canWrite || party.status === "archived"}
            type="submit"
          >
            <Plus aria-hidden="true" size={16} />
            {copy.crm.addAddress}
          </Button>
        </form>
      </WorkbenchSection>
      <WorkbenchSection title={copy.crm.relationships}>
        {party.relationships.length === 0 ? (
          <p className="px-4 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.crm.noRelationships}
          </p>
        ) : (
          <ul className="m-0 list-none p-0">
            {party.relationships.map((relationship) => (
              <li
                className="border-b border-[var(--line)] px-4 py-4 text-sm sm:px-6 lg:px-8"
                key={relationship.relationshipId}
              >
                <strong>{relationship.relationshipType}</strong>:{" "}
                {relationship.relatedPartyId}
              </li>
            ))}
          </ul>
        )}
        <form
          className="grid gap-4 border-t border-[var(--line)] px-4 py-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={(event) => onMutation("add-relationship", event)}
        >
          <Field label={copy.crm.relatedPartyId} required>
            <Input className={m3FieldClass} name="relatedPartyId" required />
          </Field>
          <Field label={copy.crm.relationshipType} required>
            <Input className={m3FieldClass} name="relationshipType" required />
          </Field>
          <Field label={copy.crm.effectiveFrom}>
            <Input className={m3FieldClass} name="effectiveFrom" type="date" />
          </Field>
          <Field label={copy.crm.effectiveTo}>
            <Input className={m3FieldClass} name="effectiveTo" type="date" />
          </Field>
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
            disabled={!runtime.canWrite || party.status === "archived"}
            type="submit"
          >
            <Plus aria-hidden="true" size={16} />
            {copy.crm.addRelationship}
          </Button>
        </form>
      </WorkbenchSection>
      <WorkbenchSection title={copy.crm.partyPreferences}>
        {party.preferences.length === 0 ? (
          <p className="px-4 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.crm.noPreferences}
          </p>
        ) : (
          <ul className="m-0 list-none p-0">
            {party.preferences.map((preference) => (
              <li
                className="border-b border-[var(--line)] px-4 py-4 text-sm sm:px-6 lg:px-8"
                key={preference.preferenceId}
              >
                <strong>{preference.channelKey}</strong>:{" "}
                {preference.allowed ? copy.crm.allowed : copy.crm.doNotContact}
              </li>
            ))}
          </ul>
        )}
        <form
          className="grid gap-4 border-t border-[var(--line)] px-4 py-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={(event) => onMutation("preference", event)}
        >
          <Field label={copy.crm.channelKey} required>
            <Input
              className={m3FieldClass}
              defaultValue="email"
              name="channelKey"
              required
            />
          </Field>
          <Field label={copy.crm.consentStatus} required>
            <NativeSelect
              className={m3FieldClass}
              defaultValue="unknown"
              name="consentStatus"
            >
              <option value="unknown">unknown</option>
              <option value="granted">granted</option>
              <option value="denied">denied</option>
              <option value="withdrawn">withdrawn</option>
            </NativeSelect>
          </Field>
          <Field label={copy.crm.consentSource}>
            <Input className={m3FieldClass} name="consentSource" />
          </Field>
          <div className="flex flex-wrap items-center gap-4">
            <BooleanField label={copy.crm.allowed} name="allowed" />
            <BooleanField label={copy.crm.doNotContact} name="doNotContact" />
          </div>
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
            disabled={!runtime.canWrite || party.status === "archived"}
            type="submit"
          >
            {copy.crm.setPreference}
          </Button>
        </form>
      </WorkbenchSection>
      <WorkbenchSection title={copy.crm.partyIdentifiers}>
        {party.identifiers.length === 0 ? (
          <p className="px-4 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.crm.noIdentifiers}
          </p>
        ) : (
          <div>
            {party.identifiers.map((identifier) => (
              <div
                className="border-b border-[var(--line)] px-4 py-5 sm:px-6 lg:px-8"
                key={identifier.identifierId}
              >
                <p className="m-0 break-words text-sm">
                  <strong>{identifier.identifierType}</strong> ·{" "}
                  {identifier.jurisdiction} · {identifier.maskedValue}
                </p>
                {revealedIdentifier?.identifierId ===
                identifier.identifierId ? (
                  <p className="break-all text-sm" role="status">
                    {copy.crm.revealedIdentifier}:{" "}
                    <strong>{revealedIdentifier.value}</strong>
                  </p>
                ) : null}
                <form
                  className="mt-4 grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end"
                  onSubmit={(event) =>
                    onMutation(
                      "reveal-identifier",
                      event,
                      identifier.identifierId,
                    )
                  }
                >
                  <Field label={copy.crm.identifierReason} required>
                    <Input className={m3FieldClass} name="reason" required />
                  </Field>
                  <Button
                    className={m3SecondaryButtonClass}
                    disabled={!runtime.canWrite}
                    type="submit"
                  >
                    {copy.crm.revealIdentifier}
                  </Button>
                </form>
              </div>
            ))}
          </div>
        )}
        <form
          className="grid gap-4 border-t border-[var(--line)] px-4 py-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={(event) => onMutation("replace-identifier", event)}
        >
          <Field label={copy.crm.identifierType} required>
            <Input className={m3FieldClass} name="identifierType" required />
          </Field>
          <Field label={copy.crm.jurisdiction} required>
            <Input
              className={m3FieldClass}
              defaultValue="CA-QC"
              name="jurisdiction"
              required
            />
          </Field>
          <Field label={copy.crm.identifierValue} required>
            <Input className={m3FieldClass} name="value" required />
          </Field>
          <Field label={copy.crm.identifierReason} required>
            <Input className={m3FieldClass} name="reason" required />
          </Field>
          <Field label={copy.crm.effectiveFrom}>
            <Input className={m3FieldClass} name="effectiveFrom" type="date" />
          </Field>
          <Field label={copy.crm.effectiveTo}>
            <Input className={m3FieldClass} name="effectiveTo" type="date" />
          </Field>
          <Button
            className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
            disabled={!runtime.canWrite || party.status === "archived"}
            type="submit"
          >
            {copy.crm.replaceIdentifier}
          </Button>
        </form>
      </WorkbenchSection>
      <WorkbenchSection title={copy.crm.archiveParty}>
        <form
          className="grid gap-4 px-4 pb-6 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end sm:px-6 lg:px-8"
          onSubmit={(event) => onMutation("archive", event)}
        >
          <Field label={copy.crm.archiveReason} required>
            <Textarea className={m3TextAreaClass} name="reason" required />
          </Field>
          <Button
            className={m3SecondaryButtonClass}
            disabled={!runtime.canWrite || party.status === "archived"}
            type="submit"
          >
            {copy.crm.archiveParty}
          </Button>
        </form>
      </WorkbenchSection>
    </div>
  );
}

function BooleanField({
  label,
  name,
}: {
  readonly label: string;
  readonly name: string;
}) {
  return (
    <label className="inline-flex min-h-11 items-center gap-2 text-sm font-bold">
      <Checkbox className="size-5" name={name} />
      {label}
    </label>
  );
}

function TaskWorkbench({
  copy,
  locale,
  onCancel,
  onComplete,
  onCreate,
  runtime,
  status,
  tasks,
}: {
  readonly copy: M3Messages;
  readonly locale: Locale;
  readonly onCancel: (event: FormEvent<HTMLFormElement>, task: TaskRow) => void;
  readonly onComplete: (task: TaskRow) => void;
  readonly onCreate: (event: FormEvent<HTMLFormElement>) => void;
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
  readonly tasks: readonly TaskRow[];
}) {
  return (
    <div>
      <WorkbenchSection
        description={copy.crm.emptyDescription}
        title={copy.crm.addTask}
      >
        <form
          className="grid gap-4 px-4 pb-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={onCreate}
        >
          <Field label={copy.crm.title} required>
            <Input className={m3FieldClass} name="title" required />
          </Field>
          <Field label={copy.crm.due} required>
            <Input
              className={m3FieldClass}
              name="dueAt"
              required
              type="datetime-local"
            />
          </Field>
          <Field label={copy.crm.assigneeMembershipId} required>
            <Input
              className={m3FieldClass}
              defaultValue={runtime.previewMode ? ids.membership : ""}
              name="assigneeMembershipId"
              required
            />
          </Field>
          <Field label={copy.crm.description}>
            <Input className={m3FieldClass} name="description" />
          </Field>
          <Field label={copy.crm.partyId}>
            <Input
              className={m3FieldClass}
              defaultValue={runtime.previewMode ? ids.partyA : ""}
              name="partyId"
            />
          </Field>
          <Field label={copy.crm.leadId}>
            <Input className={m3FieldClass} name="leadId" />
          </Field>
          <Field label={copy.crm.dealId}>
            <Input className={m3FieldClass} name="dealId" />
          </Field>
          <p className="m-0 text-sm text-muted-foreground sm:col-span-2">
            {copy.crm.relationRequired}
          </p>
          <div className="flex flex-wrap items-center gap-3 sm:col-span-2">
            <Button
              className={m3PrimaryButtonClass}
              disabled={!runtime.canWrite}
              type="submit"
            >
              <Plus aria-hidden="true" size={16} />
              {copy.crm.addTask}
            </Button>
            {status}
          </div>
        </form>
      </WorkbenchSection>
      <WorkbenchSection title={copy.crm.taskHeading}>
        {tasks.length === 0 ? (
          <p className="px-4 pb-8 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.crm.taskEmpty}
          </p>
        ) : (
          <div>
            {tasks.map((task) => (
              <article
                className="grid gap-4 border-b border-[var(--line)] px-4 py-5 last:border-b-0 sm:grid-cols-[minmax(0,1fr)_14rem_auto] sm:items-center sm:px-6 lg:px-8"
                key={task.taskId}
              >
                <div>
                  <h3 className="m-0 text-sm font-bold">{task.title}</h3>
                  <p className="mb-0 mt-1 text-xs text-muted-foreground">
                    {copy.crm.assignedTo}: {task.assigneeMembershipId}
                  </p>
                </div>
                <p className="m-0 text-sm">
                  <Clock3
                    aria-hidden="true"
                    className="mr-2 inline"
                    size={16}
                  />
                  {dateTime(task.dueAt, locale)}
                </p>
                {task.state !== "open" ? (
                  <Status
                    label={
                      task.state === "completed"
                        ? copy.crm.complete
                        : copy.common.cancel
                    }
                  />
                ) : (
                  <div className="flex flex-col gap-2">
                    <Button
                      className={m3SecondaryButtonClass}
                      disabled={!runtime.canWrite}
                      onClick={() => onComplete(task)}
                      type="button"
                    >
                      <Check aria-hidden="true" size={16} />
                      {copy.crm.complete}
                    </Button>
                    <details className="border border-[var(--line)]">
                      <summary className="flex min-h-11 cursor-pointer items-center px-3 text-sm font-bold">
                        {copy.crm.cancelTask}
                      </summary>
                      <form
                        className="grid gap-3 border-t border-[var(--line)] p-3"
                        onSubmit={(event) => onCancel(event, task)}
                      >
                        <Field label={copy.crm.taskCancelReason} required>
                          <Textarea
                            className={m3TextAreaClass}
                            name="reason"
                            required
                          />
                        </Field>
                        <Button
                          className={m3SecondaryButtonClass}
                          disabled={!runtime.canWrite}
                          type="submit"
                        >
                          {copy.crm.cancelTask}
                        </Button>
                      </form>
                    </details>
                  </div>
                )}
              </article>
            ))}
          </div>
        )}
      </WorkbenchSection>
    </div>
  );
}

function AppointmentWorkbench({
  appointments,
  copy,
  locale,
  onCreate,
  onTransition,
  runtime,
  status,
}: {
  readonly appointments: readonly AppointmentRow[];
  readonly copy: M3Messages;
  readonly locale: Locale;
  readonly onCreate: (event: FormEvent<HTMLFormElement>) => void;
  readonly onTransition: (
    event: FormEvent<HTMLFormElement>,
    appointment: AppointmentRow,
  ) => void;
  readonly runtime: M3OperatorRuntimeState;
  readonly status: ReactNode;
}) {
  return (
    <div>
      <WorkbenchSection
        description={copy.crm.appointmentTimezone}
        title={copy.crm.addAppointment}
      >
        <form
          className="grid gap-4 px-4 pb-6 sm:grid-cols-2 sm:px-6 lg:px-8"
          onSubmit={onCreate}
        >
          <Field label={copy.crm.title} required>
            <Input className={m3FieldClass} name="title" required />
          </Field>
          <Field label={copy.crm.timezone} required>
            <Input
              className={m3FieldClass}
              defaultValue="America/Toronto"
              name="timezone"
              required
            />
          </Field>
          <Field label={copy.crm.startsAt} required>
            <Input
              className={m3FieldClass}
              name="startsAt"
              required
              type="datetime-local"
            />
          </Field>
          <Field label={copy.crm.endsAt} required>
            <Input
              className={m3FieldClass}
              name="endsAt"
              required
              type="datetime-local"
            />
          </Field>
          <Field label={copy.crm.leadId}>
            <Input
              className={m3FieldClass}
              defaultValue={runtime.previewMode ? ids.leadA : ""}
              name="leadId"
            />
          </Field>
          <Field label={copy.crm.dealId}>
            <Input className={m3FieldClass} name="dealId" />
          </Field>
          <div className="sm:col-span-2">
            <Field label={copy.crm.appointmentNotes}>
              <Textarea className={m3TextAreaClass} name="notes" />
            </Field>
          </div>
          <p className="m-0 text-sm text-muted-foreground sm:col-span-2">
            {copy.crm.relationRequired}
          </p>
          <div className="flex flex-wrap items-center gap-3 sm:col-span-2">
            <Button
              className={m3PrimaryButtonClass}
              disabled={!runtime.canWrite}
              type="submit"
            >
              <CalendarDays aria-hidden="true" size={16} />
              {copy.crm.addAppointment}
            </Button>
            {status}
          </div>
        </form>
      </WorkbenchSection>
      <WorkbenchSection title={copy.crm.appointmentHeading}>
        {appointments.length === 0 ? (
          <p className="px-4 pb-8 text-sm text-muted-foreground sm:px-6 lg:px-8">
            {copy.crm.appointmentEmpty}
          </p>
        ) : (
          <div>
            {appointments.map((appointment) => (
              <article
                className="grid gap-4 border-b border-[var(--line)] px-4 py-5 last:border-b-0 sm:grid-cols-[minmax(0,1fr)_minmax(15rem,0.55fr)] sm:items-center sm:px-6 lg:px-8"
                key={appointment.appointmentId}
              >
                <div>
                  <Status
                    label={
                      copy.crm.appointmentStatusLabels[appointment.status] ??
                      appointment.status
                    }
                  />
                  <h3 className="m-0 text-sm font-bold">{appointment.title}</h3>
                  <p className="mb-0 mt-1 text-xs text-muted-foreground">
                    {appointment.timezone}
                  </p>
                </div>
                <p className="m-0 text-sm">
                  <CalendarDays
                    aria-hidden="true"
                    className="mr-2 inline"
                    size={16}
                  />
                  {dateTime(appointment.startsAt, locale)} –{" "}
                  {dateTime(appointment.endsAt, locale)}
                </p>
                {appointment.status === "scheduled" ? (
                  <AppointmentActions
                    appointment={appointment}
                    copy={copy}
                    onTransition={onTransition}
                    runtime={runtime}
                  />
                ) : null}
              </article>
            ))}
          </div>
        )}
      </WorkbenchSection>
    </div>
  );
}

function AppointmentActions({
  appointment,
  copy,
  onTransition,
  runtime,
}: {
  readonly appointment: AppointmentRow;
  readonly copy: M3Messages;
  readonly onTransition: (
    event: FormEvent<HTMLFormElement>,
    appointment: AppointmentRow,
  ) => void;
  readonly runtime: M3OperatorRuntimeState;
}) {
  const [targetStatus, setTargetStatus] = useState<
    "cancelled" | "completed" | "no_show"
  >("completed");
  return (
    <details className="border border-[var(--line)] sm:col-span-2">
      <summary className="flex min-h-11 cursor-pointer items-center px-3 text-sm font-bold">
        {copy.crm.updateAppointment}
      </summary>
      <form
        className="grid gap-3 border-t border-[var(--line)] p-3 sm:grid-cols-2"
        onSubmit={(event) => onTransition(event, appointment)}
      >
        <Field label={copy.crm.transitionTarget} required>
          <NativeSelect
            className={m3FieldClass}
            name="targetStatus"
            onChange={(event) =>
              setTargetStatus(
                event.target.value as "cancelled" | "completed" | "no_show",
              )
            }
            value={targetStatus}
          >
            {(["completed", "cancelled", "no_show"] as const).map((status) => (
              <option key={status} value={status}>
                {copy.crm.appointmentStatusLabels[status]}
              </option>
            ))}
          </NativeSelect>
        </Field>
        {targetStatus === "completed" ? (
          <Field label={copy.crm.appointmentOutcome} required>
            <Textarea className={m3TextAreaClass} name="outcome" required />
          </Field>
        ) : (
          <Field label={copy.crm.appointmentReason} required>
            <Textarea className={m3TextAreaClass} name="reason" required />
          </Field>
        )}
        <Button
          className={`${m3SecondaryButtonClass} justify-self-start sm:col-span-2`}
          disabled={!runtime.canWrite}
          type="submit"
        >
          {copy.crm.updateAppointment}
        </Button>
      </form>
    </details>
  );
}
