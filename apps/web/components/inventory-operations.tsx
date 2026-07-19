"use client";

import { Button } from "@vynlo/ui-web/components/button";
import { Input } from "@vynlo/ui-web/components/input";
import { NativeSelect } from "@vynlo/ui-web/components/native-select";
import { Textarea } from "@vynlo/ui-web/components/textarea";
import {
  ArrowLeft,
  ArrowRightLeft,
  CircleAlert,
  Images,
  LoaderCircle,
  RefreshCw,
  RotateCcw,
  Save,
} from "lucide-react";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import { z } from "zod";
import type { InventoryOperationsCopy } from "../i18n/inventory-operations-messages";
import type { Locale } from "../i18n/messages";
import {
  formatMinorMoney,
  minorMoneyToMajorInput,
  parseMajorMoneyToMinor,
} from "../lib/inventory-money";
import { getBrowserSupabase } from "../lib/supabase-browser";
import { OperatorShell } from "./operator-shell";

type Phase = "error" | "loading" | "ready";
type ActionState = "conflict" | "error" | "idle" | "saved" | "step_up";

interface WorkspaceOption {
  readonly id: string;
  readonly name: string;
}

const uuidSchema = z.string().uuid();
const bigintTextSchema = z.string().regex(/^(?:0|[1-9]\d{0,18})$/u);
const signedBigintTextSchema = z.string().regex(/^-?(?:0|[1-9]\d{0,18})$/u);
const canonicalStatusSchema = z.enum([
  "draft",
  "active",
  "pending",
  "closed",
  "archived",
]);
const vehicleFactsSchema = z
  .object({
    bodyType: z.string().nullable(),
    cylinders: z.number().int().nullable(),
    drivetrain: z.string().nullable(),
    engineLiters: z.string().nullable(),
    factsVersion: z.number().int().positive(),
    fuelType: z.string().nullable(),
    horsepower: z.number().int().nullable(),
    make: z.string().nullable(),
    model: z.string().nullable(),
    modelYear: z.number().int().nullable(),
    transmission: z.string().nullable(),
    trimName: z.string().nullable(),
    vin: z.string(),
  })
  .strict();
const detailSchema = z
  .object({
    acquisitionDate: z.string().nullable(),
    acquiredAt: z.string().nullable(),
    advertisedPriceMinor: bigintTextSchema.nullable(),
    aggregateVersion: z.number().int().positive(),
    allowedTransitions: z.array(
      z
        .object({
          canonicalStatus: canonicalStatusSchema,
          key: z.string(),
          labels: z.record(z.string(), z.string()),
          reasonRequired: z.boolean(),
          toStateKey: z.string(),
        })
        .strict(),
    ),
    availableAt: z.string().nullable(),
    capabilities: z
      .object({
        canCreateCosts: z.boolean(),
        canOverrideFacts: z.boolean(),
        canReadCosts: z.boolean(),
        canReadInternal: z.boolean(),
        canReverseCosts: z.boolean(),
        canTransferLocation: z.boolean(),
        canTransitionWorkflow: z.boolean(),
        canUpdateDetails: z.boolean(),
        canUpdateInternal: z.boolean(),
        hasRecentStrongAuthentication: z.boolean(),
      })
      .strict(),
    canonicalStatus: canonicalStatusSchema,
    closedAt: z.string().nullable(),
    conditionKey: z.string().nullable(),
    currencyCode: z.string().regex(/^[A-Z]{3}$/u),
    estimatedGrossMinor: signedBigintTextSchema.nullable(),
    expectedSalePriceMinor: bigintTextSchema.nullable(),
    internalNotes: z.string().nullable(),
    inventoryUnitId: uuidSchema,
    location: z
      .object({ id: uuidSchema, name: z.string() })
      .strict()
      .nullable(),
    odometer: z
      .object({ unit: z.enum(["km", "mi"]), value: bigintTextSchema })
      .strict()
      .nullable(),
    postedCostMinor: bigintTextSchema.nullable(),
    publicNotes: z.string().nullable(),
    soldAt: z.string().nullable(),
    stockNumber: z.string(),
    updatedAt: z.string(),
    vehicleFacts: vehicleFactsSchema,
    vehicleId: uuidSchema,
    workflowConfigurationVersion: z.string(),
    workflowInstanceVersion: z.number().int().positive(),
    workflowStateKey: z.string(),
  })
  .strict();
const locationSchema = z
  .object({
    id: uuidSchema,
    key: z.string(),
    locale: z.string().nullable(),
    name: z.string(),
    timezone: z.string().nullable(),
    version: z.number().int().positive(),
  })
  .strict();
const costCategorySchema = z
  .object({
    id: uuidSchema,
    key: z.string(),
    labels: z.record(z.string(), z.string()),
    version: z.number().int().positive(),
  })
  .strict();
const costEntrySchema = z
  .object({
    aggregateVersion: z.number().int().positive(),
    amountMinor: bigintTextSchema,
    categoryDefinitionId: uuidSchema,
    categoryKey: z.string(),
    categoryLabels: z.record(z.string(), z.string()),
    createdAt: z.string(),
    currencyCode: z.string(),
    description: z.string().nullable(),
    effectiveStatus: z.enum(["posted", "reversed", "reversal"]),
    entryKind: z.enum(["cost", "reversal"]),
    id: uuidSchema,
    incurredOn: z.string(),
    reversalOfId: uuidSchema.nullable(),
    supportingFileId: uuidSchema.nullable(),
    vendorPartyId: uuidSchema.nullable(),
  })
  .strict();
const costsSchema = z
  .object({
    aggregateVersion: z.number().int().positive(),
    canCreate: z.boolean(),
    canReverse: z.boolean(),
    categories: z.array(costCategorySchema),
    currencyCode: z.string(),
    entries: z.array(costEntrySchema),
    estimatedGrossMinor: signedBigintTextSchema.nullable(),
    hasRecentStrongAuthentication: z.boolean(),
    inventoryUnitId: uuidSchema,
    lastCostAt: z.string().nullable(),
    nextCursor: z.unknown().nullable(),
    postedCostMinor: bigintTextSchema,
    postedEntryCount: z.number().int().min(0),
  })
  .strict();

type InventoryDetail = z.infer<typeof detailSchema>;
type InventoryCosts = z.infer<typeof costsSchema>;
type InventoryLocation = z.infer<typeof locationSchema>;

interface DetailsDraft {
  readonly acquisitionDate: string;
  readonly advertisedPrice: string;
  readonly conditionKey: string;
  readonly expectedSalePrice: string;
  readonly internalNotes: string;
  readonly odometerUnit: "km" | "mi";
  readonly odometerValue: string;
  readonly publicNotes: string;
}

interface FactsDraft {
  readonly bodyType: string;
  readonly cylinders: string;
  readonly drivetrain: string;
  readonly engineLiters: string;
  readonly fuelType: string;
  readonly horsepower: string;
  readonly make: string;
  readonly model: string;
  readonly modelYear: string;
  readonly reason: string;
  readonly transmission: string;
  readonly trimName: string;
}

const previewWorkspace: WorkspaceOption = Object.freeze({
  id: "00000000-0000-4000-8000-000000000201",
  name: "Sample workspace",
});
const previewLocations: readonly InventoryLocation[] = Object.freeze([
  {
    id: "00000000-0000-4000-8000-000000000221",
    key: "synthetic.showroom",
    locale: "en-CA",
    name: "Main showroom",
    timezone: "America/Toronto",
    version: 1,
  },
  {
    id: "00000000-0000-4000-8000-000000000222",
    key: "synthetic.north_lot",
    locale: "en-CA",
    name: "North lot",
    timezone: "America/Toronto",
    version: 1,
  },
]);
const previewDetail: InventoryDetail = {
  acquisitionDate: "2026-07-04",
  acquiredAt: "2026-07-04T14:00:00.000Z",
  advertisedPriceMinor: "5499500",
  aggregateVersion: 6,
  allowedTransitions: [
    {
      canonicalStatus: "active",
      key: "in_preparation__ready",
      labels: { en: "Ready for sale", fr: "Prêt à vendre" },
      reasonRequired: false,
      toStateKey: "ready",
    },
  ],
  availableAt: null,
  capabilities: {
    canCreateCosts: true,
    canOverrideFacts: true,
    canReadCosts: true,
    canReadInternal: true,
    canReverseCosts: true,
    canTransferLocation: true,
    canTransitionWorkflow: true,
    canUpdateDetails: true,
    canUpdateInternal: true,
    hasRecentStrongAuthentication: true,
  },
  canonicalStatus: "active",
  closedAt: null,
  conditionKey: "used.ready",
  currencyCode: "CAD",
  estimatedGrossMinor: "1449500",
  expectedSalePriceMinor: "5600000",
  internalNotes: "Synthetic inspection complete.",
  inventoryUnitId: "00000000-0000-4000-8000-000000000211",
  location: { id: previewLocations[0]!.id, name: previewLocations[0]!.name },
  odometer: { unit: "km", value: "28400" },
  postedCostMinor: "4150500",
  publicNotes: "Synthetic single-owner fixture.",
  soldAt: null,
  stockNumber: "SYN-24018",
  updatedAt: "2026-07-16T14:00:00.000Z",
  vehicleFacts: {
    bodyType: "SUV",
    cylinders: 4,
    drivetrain: "AWD",
    engineLiters: "2.0",
    factsVersion: 1,
    fuelType: "Gasoline",
    horsepower: 247,
    make: "Volvo",
    model: "XC60",
    modelYear: 2024,
    transmission: "Automatic",
    trimName: "Plus",
    vin: "1HGCM82633A004352",
  },
  vehicleId: "00000000-0000-4000-8000-000000000241",
  workflowConfigurationVersion: "1.0.0",
  workflowInstanceVersion: 6,
  workflowStateKey: "in_preparation",
};
const previewCosts: InventoryCosts = {
  aggregateVersion: 6,
  canCreate: true,
  canReverse: true,
  categories: [
    {
      id: "00000000-0000-4000-8000-000000000251",
      key: "reconditioning",
      labels: { en: "Reconditioning", fr: "Remise en état" },
      version: 1,
    },
    {
      id: "00000000-0000-4000-8000-000000000252",
      key: "transport",
      labels: { en: "Transport", fr: "Transport" },
      version: 1,
    },
  ],
  currencyCode: "CAD",
  entries: [
    {
      aggregateVersion: 6,
      amountMinor: "15000",
      categoryDefinitionId: "00000000-0000-4000-8000-000000000251",
      categoryKey: "reconditioning",
      categoryLabels: { en: "Reconditioning", fr: "Remise en état" },
      createdAt: "2026-07-12T14:00:00.000Z",
      currencyCode: "CAD",
      description: "Synthetic detailing",
      effectiveStatus: "posted",
      entryKind: "cost",
      id: "00000000-0000-4000-8000-000000000261",
      incurredOn: "2026-07-12",
      reversalOfId: null,
      supportingFileId: null,
      vendorPartyId: null,
    },
  ],
  estimatedGrossMinor: "1449500",
  hasRecentStrongAuthentication: true,
  inventoryUnitId: previewDetail.inventoryUnitId,
  lastCostAt: "2026-07-12T14:00:00.000Z",
  nextCursor: null,
  postedCostMinor: "4150500",
  postedEntryCount: 4,
};

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function parseEnvelope<T>(schema: z.ZodType<T>, value: unknown): T {
  const envelope = record(value);
  const result = schema.safeParse(envelope?.data);
  if (!result.success)
    throw new TypeError("invalid_inventory_operation_response");
  return result.data;
}

function parseLocationsEnvelope(value: unknown): readonly InventoryLocation[] {
  const envelope = record(value);
  const data = record(envelope?.data);
  const result = z.array(locationSchema).max(200).safeParse(data?.items);
  if (!result.success)
    throw new TypeError("invalid_inventory_locations_response");
  return result.data;
}

function parseWorkspaceOptions(value: unknown): readonly WorkspaceOption[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((membership) => {
    const source = record(membership);
    const relation = source?.workspaces;
    const workspace = Array.isArray(relation)
      ? record(relation[0])
      : record(relation);
    return typeof workspace?.id === "string" &&
      typeof workspace.name === "string"
      ? [{ id: workspace.id, name: workspace.name }]
      : [];
  });
}

function minorToMajor(value: string | null, currencyCode: string): string {
  if (value === null) return "";
  return minorMoneyToMajorInput(value, currencyCode);
}

function detailsDraft(detail: InventoryDetail): DetailsDraft {
  return {
    acquisitionDate: detail.acquisitionDate ?? "",
    advertisedPrice: minorToMajor(
      detail.advertisedPriceMinor,
      detail.currencyCode,
    ),
    conditionKey: detail.conditionKey ?? "",
    expectedSalePrice: minorToMajor(
      detail.expectedSalePriceMinor,
      detail.currencyCode,
    ),
    internalNotes: detail.internalNotes ?? "",
    odometerUnit: detail.odometer?.unit ?? "km",
    odometerValue: detail.odometer?.value ?? "",
    publicNotes: detail.publicNotes ?? "",
  };
}

function factsDraft(detail: InventoryDetail): FactsDraft {
  const facts = detail.vehicleFacts;
  return {
    bodyType: facts.bodyType ?? "",
    cylinders: facts.cylinders === null ? "" : String(facts.cylinders),
    drivetrain: facts.drivetrain ?? "",
    engineLiters: facts.engineLiters ?? "",
    fuelType: facts.fuelType ?? "",
    horsepower: facts.horsepower === null ? "" : String(facts.horsepower),
    make: facts.make ?? "",
    model: facts.model ?? "",
    modelYear: facts.modelYear === null ? "" : String(facts.modelYear),
    reason: "",
    transmission: facts.transmission ?? "",
    trimName: facts.trimName ?? "",
  };
}

function nullableText(value: string): string | null {
  return value.trim() === "" ? null : value.trim();
}

function nullableInteger(value: string): number | null {
  const normalized = value.trim();
  if (normalized === "") return null;
  if (!/^\d+$/u.test(normalized)) throw new TypeError("invalid_integer");
  return Number(normalized);
}

function localizedLabel(
  labels: Readonly<Record<string, string>>,
  locale: Locale,
  fallback: string,
): string {
  return labels[locale] ?? labels.en ?? labels.fr ?? fallback;
}

function statusText(
  copy: InventoryOperationsCopy,
  status: InventoryDetail["canonicalStatus"],
): string {
  switch (status) {
    case "active":
      return copy.statusActive;
    case "archived":
      return copy.archiveStatus;
    case "closed":
      return copy.cancelStatus;
    case "draft":
      return copy.statusDraft;
    case "pending":
      return copy.statusPending;
  }
}

export function InventoryOperations({
  copy,
  inventoryUnitId,
  locale,
  previewMode,
  requestedWorkspaceId,
}: Readonly<{
  copy: InventoryOperationsCopy;
  inventoryUnitId: string;
  locale: Locale;
  previewMode: boolean;
  requestedWorkspaceId?: string;
}>) {
  const router = useRouter();
  const previewEnabled = process.env.NODE_ENV !== "production" && previewMode;
  const activeWorkspaceId = useRef("");
  const idempotencyKeys = useRef(new Map<string, string>());
  const loadAbortController = useRef<AbortController | null>(null);
  const loadRequestSequence = useRef(0);
  const mutationInFlight = useRef(false);
  const mutationSequence = useRef(0);
  const [actionState, setActionState] = useState<ActionState>("idle");
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [costAmount, setCostAmount] = useState("");
  const [costCategoryId, setCostCategoryId] = useState("");
  const [costDate, setCostDate] = useState("");
  const [costDescription, setCostDescription] = useState("");
  const [costs, setCosts] = useState<InventoryCosts | null>(null);
  const [detail, setDetail] = useState<InventoryDetail | null>(null);
  const [detailForm, setDetailForm] = useState<DetailsDraft | null>(null);
  const [factsForm, setFactsForm] = useState<FactsDraft | null>(null);
  const [locations, setLocations] = useState<readonly InventoryLocation[]>([]);
  const [phase, setPhase] = useState<Phase>("loading");
  const [reversalCostId, setReversalCostId] = useState("");
  const [reversalDate, setReversalDate] = useState("");
  const [reversalReason, setReversalReason] = useState("");
  const [targetLocationId, setTargetLocationId] = useState("");
  const [transferReason, setTransferReason] = useState("");
  const [transitionKey, setTransitionKey] = useState("");
  const [transitionReason, setTransitionReason] = useState("");
  const [workspaceId, setWorkspaceId] = useState("");
  const [workspaces, setWorkspaces] = useState<readonly WorkspaceOption[]>([]);

  const applyLoadedData = useCallback(
    (
      nextDetail: InventoryDetail,
      nextLocations: readonly InventoryLocation[],
      nextCosts: InventoryCosts | null,
    ) => {
      setDetail(nextDetail);
      setLocations(nextLocations);
      setCosts(nextCosts);
      setDetailForm(detailsDraft(nextDetail));
      setFactsForm(factsDraft(nextDetail));
      setTargetLocationId(
        nextDetail.location?.id ?? nextLocations[0]?.id ?? "",
      );
      setTransitionKey(nextDetail.allowedTransitions[0]?.key ?? "");
      setCostCategoryId(nextCosts?.categories[0]?.id ?? "");
      setReversalCostId(
        nextCosts?.entries.find(
          (entry) =>
            entry.entryKind === "cost" && entry.effectiveStatus === "posted",
        )?.id ?? "",
      );
      setPhase("ready");
    },
    [],
  );

  const loadData = useCallback(
    async (targetWorkspaceId: string) => {
      const sequence = ++loadRequestSequence.current;
      loadAbortController.current?.abort();
      const abortController = new AbortController();
      loadAbortController.current = abortController;
      const isCurrentRequest = () =>
        activeWorkspaceId.current === targetWorkspaceId &&
        loadRequestSequence.current === sequence &&
        !abortController.signal.aborted;
      if (!isCurrentRequest()) return;
      setPhase("loading");
      setActionState("idle");
      try {
        if (previewEnabled) {
          await Promise.resolve();
          if (isCurrentRequest()) {
            applyLoadedData(previewDetail, previewLocations, previewCosts);
          }
          return;
        }
        const session = (await getBrowserSupabase().auth.getSession()).data
          .session;
        if (!session) {
          router.replace("/login");
          return;
        }
        const headers = () => ({
          Authorization: `Bearer ${session.access_token}`,
          "X-Correlation-Id": crypto.randomUUID(),
          "X-Request-Id": crypto.randomUUID(),
          "X-Workspace-Id": targetWorkspaceId,
        });
        const [detailResponse, locationsResponse] = await Promise.all([
          fetch(`/api/v1/inventory-units/${inventoryUnitId}`, {
            cache: "no-store",
            headers: headers(),
            signal: abortController.signal,
          }),
          fetch("/api/v1/locations", {
            cache: "no-store",
            headers: headers(),
            signal: abortController.signal,
          }),
        ]);
        if (!detailResponse.ok || !locationsResponse.ok) {
          throw new TypeError("inventory_detail_request_failed");
        }
        const nextDetail = parseEnvelope(
          detailSchema,
          await detailResponse.json(),
        );
        const nextLocations = parseLocationsEnvelope(
          await locationsResponse.json(),
        );
        let nextCosts: InventoryCosts | null = null;
        if (nextDetail.capabilities.canReadCosts) {
          if (!isCurrentRequest()) return;
          const response = await fetch(
            `/api/v1/inventory-units/${inventoryUnitId}/costs?pageSize=100`,
            {
              cache: "no-store",
              headers: headers(),
              signal: abortController.signal,
            },
          );
          if (!response.ok)
            throw new TypeError("inventory_cost_request_failed");
          nextCosts = parseEnvelope(costsSchema, await response.json());
        }
        if (isCurrentRequest()) {
          applyLoadedData(nextDetail, nextLocations, nextCosts);
        }
      } catch {
        if (isCurrentRequest()) setPhase("error");
      }
    },
    [applyLoadedData, inventoryUnitId, previewEnabled, router],
  );

  useEffect(() => {
    let active = true;
    async function initialize() {
      if (previewEnabled) {
        setWorkspaces([previewWorkspace]);
        activeWorkspaceId.current = previewWorkspace.id;
        setWorkspaceId(previewWorkspace.id);
        await loadData(previewWorkspace.id);
        return;
      }
      let initializationWorkspaceId = "";
      try {
        const client = getBrowserSupabase();
        const session = (await client.auth.getSession()).data.session;
        if (!session) {
          router.replace("/login");
          return;
        }
        const memberships = await client
          .from("workspace_memberships")
          .select("id,workspaces!inner(id,name)")
          .eq("user_id", session.user.id)
          .eq("status", "active");
        if (memberships.error) throw memberships.error;
        const options = parseWorkspaceOptions(memberships.data);
        const first =
          options.find((workspace) => workspace.id === requestedWorkspaceId) ??
          options[0];
        if (!first) throw new TypeError("workspace_required");
        initializationWorkspaceId = first.id;
        if (active) {
          setWorkspaces(options);
          activeWorkspaceId.current = first.id;
          setWorkspaceId(first.id);
          await loadData(first.id);
        }
      } catch {
        if (
          active &&
          (!initializationWorkspaceId ||
            activeWorkspaceId.current === initializationWorkspaceId)
        ) {
          setPhase("error");
        }
      }
    }
    void initialize();
    return () => {
      active = false;
      loadRequestSequence.current += 1;
      mutationSequence.current += 1;
      loadAbortController.current?.abort();
    };
  }, [loadData, previewEnabled, requestedWorkspaceId, router]);

  function chooseWorkspace(nextWorkspaceId: string) {
    if (
      busyAction ||
      mutationInFlight.current ||
      !workspaces.some((workspace) => workspace.id === nextWorkspaceId)
    )
      return;
    activeWorkspaceId.current = nextWorkspaceId;
    mutationSequence.current += 1;
    setWorkspaceId(nextWorkspaceId);
    setDetail(null);
    setDetailForm(null);
    setFactsForm(null);
    setLocations([]);
    setCosts(null);
    void loadData(nextWorkspaceId);
  }

  async function executeCommand(
    action: string,
    path: string,
    body: unknown,
    method: "PATCH" | "POST" = "POST",
    previewUpdate?: () => void,
  ) {
    const targetWorkspaceId = workspaceId;
    if (
      !targetWorkspaceId ||
      activeWorkspaceId.current !== targetWorkspaceId ||
      busyAction ||
      mutationInFlight.current
    )
      return;
    const sequence = ++mutationSequence.current;
    const isCurrentMutation = () =>
      activeWorkspaceId.current === targetWorkspaceId &&
      mutationSequence.current === sequence;
    mutationInFlight.current = true;
    setBusyAction(action);
    setActionState("idle");
    try {
      if (previewEnabled) {
        await Promise.resolve();
        if (isCurrentMutation()) previewUpdate?.();
      } else {
        const session = (await getBrowserSupabase().auth.getSession()).data
          .session;
        if (!session) {
          router.replace("/login");
          return;
        }
        const fingerprint = `${targetWorkspaceId}:${method}:${path}:${JSON.stringify(body)}`;
        let idempotencyKey = idempotencyKeys.current.get(fingerprint);
        if (!idempotencyKey) {
          idempotencyKey = crypto.randomUUID();
          idempotencyKeys.current.set(fingerprint, idempotencyKey);
        }
        const response = await fetch(path, {
          body: JSON.stringify(body),
          headers: {
            Authorization: `Bearer ${session.access_token}`,
            "Content-Type": "application/json",
            "Idempotency-Key": idempotencyKey,
            "X-Correlation-Id": crypto.randomUUID(),
            "X-Request-Id": crypto.randomUUID(),
            "X-Workspace-Id": targetWorkspaceId,
          },
          method,
        });
        if (response.status === 409) {
          if (isCurrentMutation()) setActionState("conflict");
          return;
        }
        if (response.status === 403) {
          if (isCurrentMutation()) setActionState("step_up");
          return;
        }
        if (!response.ok) throw new TypeError("inventory_command_failed");
        await loadData(targetWorkspaceId);
      }
      if (isCurrentMutation()) setActionState("saved");
    } catch {
      if (isCurrentMutation()) setActionState("error");
    } finally {
      if (mutationSequence.current === sequence) {
        mutationInFlight.current = false;
        setBusyAction(null);
      }
    }
  }

  function submitDetails(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!detail || !detailForm) return;
    try {
      const advertisedPriceMinor = parseMajorMoneyToMinor(
        detailForm.advertisedPrice,
        detail.currencyCode,
      );
      const expectedSalePriceMinor = parseMajorMoneyToMinor(
        detailForm.expectedSalePrice,
        detail.currencyCode,
      );
      const odometerValue = nullableInteger(detailForm.odometerValue);
      const body = {
        acquisitionDate: nullableText(detailForm.acquisitionDate),
        acquiredAt: detail.acquiredAt,
        advertisedPriceMinor:
          advertisedPriceMinor === null ? null : advertisedPriceMinor,
        availableAt: detail.availableAt,
        conditionKey: nullableText(detailForm.conditionKey),
        expectedSalePrice:
          expectedSalePriceMinor === null
            ? null
            : {
                amountMinor: expectedSalePriceMinor,
                currencyCode: detail.currencyCode,
              },
        expectedVersion: detail.aggregateVersion,
        ...(detail.capabilities.canUpdateInternal
          ? { internalNotes: nullableText(detailForm.internalNotes) }
          : {}),
        odometer:
          odometerValue === null
            ? null
            : { unit: detailForm.odometerUnit, value: odometerValue },
        publicNotes: nullableText(detailForm.publicNotes),
      };
      void executeCommand(
        "details",
        `/api/v1/inventory-units/${detail.inventoryUnitId}`,
        body,
        "PATCH",
        () => {
          const next = {
            ...detail,
            acquisitionDate: body.acquisitionDate,
            advertisedPriceMinor,
            aggregateVersion: detail.aggregateVersion + 1,
            conditionKey: body.conditionKey,
            expectedSalePriceMinor,
            internalNotes:
              "internalNotes" in body
                ? body.internalNotes
                : detail.internalNotes,
            odometer:
              body.odometer === null
                ? null
                : {
                    unit: body.odometer.unit,
                    value: String(body.odometer.value),
                  },
            publicNotes: body.publicNotes,
            workflowInstanceVersion: detail.workflowInstanceVersion + 1,
          } satisfies InventoryDetail;
          setDetail(next);
          setDetailForm(detailsDraft(next));
        },
      );
    } catch {
      setActionState("error");
    }
  }

  function submitTransfer(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!detail) return;
    void executeCommand(
      "location",
      `/api/v1/inventory-units/${detail.inventoryUnitId}/location-transfers`,
      {
        expectedVersion: detail.aggregateVersion,
        reason: transferReason,
        toLocationId: targetLocationId,
      },
      "POST",
      () => {
        const location = locations.find((item) => item.id === targetLocationId);
        if (!location) return;
        setDetail((current) =>
          current
            ? {
                ...current,
                aggregateVersion: current.aggregateVersion + 1,
                location: { id: location.id, name: location.name },
                workflowInstanceVersion: current.workflowInstanceVersion + 1,
              }
            : current,
        );
        setTransferReason("");
      },
    );
  }

  function submitTransition(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!detail) return;
    const transition = detail.allowedTransitions.find(
      (item) => item.key === transitionKey,
    );
    if (!transition) return;
    void executeCommand(
      "transition",
      `/api/v1/inventory-units/${detail.inventoryUnitId}/transition`,
      {
        expectedVersion: detail.aggregateVersion,
        reason: nullableText(transitionReason),
        transitionKey,
      },
      "POST",
      () => {
        setDetail((current) =>
          current
            ? {
                ...current,
                aggregateVersion: current.aggregateVersion + 1,
                allowedTransitions: [],
                canonicalStatus: transition.canonicalStatus,
                workflowInstanceVersion: current.workflowInstanceVersion + 1,
                workflowStateKey: transition.toStateKey,
              }
            : current,
        );
        setTransitionReason("");
      },
    );
  }

  function submitCost(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!detail || !costs) return;
    try {
      const amountMinor = parseMajorMoneyToMinor(
        costAmount,
        detail.currencyCode,
      );
      if (amountMinor === null) throw new TypeError("cost_amount_required");
      void executeCommand(
        "cost",
        `/api/v1/inventory-units/${detail.inventoryUnitId}/costs`,
        {
          amountMinor,
          categoryDefinitionId: costCategoryId,
          currencyCode: detail.currencyCode,
          description: nullableText(costDescription),
          expectedVersion: detail.aggregateVersion,
          incurredOn: costDate,
          supportingFileId: null,
          vendorPartyId: null,
        },
        "POST",
        () => {
          const category = costs.categories.find(
            (item) => item.id === costCategoryId,
          );
          if (!category) return;
          const id = crypto.randomUUID();
          const nextPosted = (
            BigInt(costs.postedCostMinor) + BigInt(amountMinor)
          ).toString();
          const entry = {
            aggregateVersion: detail.aggregateVersion + 1,
            amountMinor,
            categoryDefinitionId: category.id,
            categoryKey: category.key,
            categoryLabels: category.labels,
            createdAt: new Date().toISOString(),
            currencyCode: detail.currencyCode,
            description: nullableText(costDescription),
            effectiveStatus: "posted" as const,
            entryKind: "cost" as const,
            id,
            incurredOn: costDate,
            reversalOfId: null,
            supportingFileId: null,
            vendorPartyId: null,
          };
          setCosts({
            ...costs,
            aggregateVersion: costs.aggregateVersion + 1,
            entries: [entry, ...costs.entries],
            postedCostMinor: nextPosted,
            postedEntryCount: costs.postedEntryCount + 1,
          });
          setDetail({
            ...detail,
            aggregateVersion: detail.aggregateVersion + 1,
            postedCostMinor: nextPosted,
            workflowInstanceVersion: detail.workflowInstanceVersion + 1,
          });
          setCostAmount("");
          setCostDescription("");
          setReversalCostId(id);
        },
      );
    } catch {
      setActionState("error");
    }
  }

  function submitReversal(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!detail || !costs || !reversalCostId) return;
    const selected = costs.entries.find((entry) => entry.id === reversalCostId);
    if (!selected) return;
    void executeCommand(
      "reversal",
      `/api/v1/inventory-costs/${selected.id}/reversal`,
      {
        expectedVersion: detail.aggregateVersion,
        reason: reversalReason,
        reversedOn: reversalDate,
      },
      "POST",
      () => {
        const nextPosted = (
          BigInt(costs.postedCostMinor) - BigInt(selected.amountMinor)
        ).toString();
        setCosts({
          ...costs,
          aggregateVersion: costs.aggregateVersion + 1,
          entries: costs.entries.map((entry) =>
            entry.id === selected.id
              ? { ...entry, effectiveStatus: "reversed" as const }
              : entry,
          ),
          postedCostMinor: nextPosted,
        });
        setDetail({
          ...detail,
          aggregateVersion: detail.aggregateVersion + 1,
          postedCostMinor: nextPosted,
          workflowInstanceVersion: detail.workflowInstanceVersion + 1,
        });
        setReversalReason("");
        setReversalCostId("");
      },
    );
  }

  function submitFacts(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!detail || !factsForm) return;
    try {
      const facts = {
        bodyType: nullableText(factsForm.bodyType),
        cylinders: nullableInteger(factsForm.cylinders),
        drivetrain: nullableText(factsForm.drivetrain),
        engineLiters: nullableText(factsForm.engineLiters),
        fuelType: nullableText(factsForm.fuelType),
        horsepower: nullableInteger(factsForm.horsepower),
        make: nullableText(factsForm.make),
        model: nullableText(factsForm.model),
        modelYear: nullableInteger(factsForm.modelYear),
        transmission: nullableText(factsForm.transmission),
        trimName: nullableText(factsForm.trimName),
      };
      void executeCommand(
        "facts",
        `/api/v1/vehicles/${detail.vehicleId}/facts-override`,
        {
          expectedFactsVersion: detail.vehicleFacts.factsVersion,
          facts,
          reason: factsForm.reason,
        },
        "POST",
        () => {
          const next = {
            ...detail,
            vehicleFacts: {
              ...facts,
              factsVersion: detail.vehicleFacts.factsVersion + 1,
              vin: detail.vehicleFacts.vin,
            },
          } satisfies InventoryDetail;
          setDetail(next);
          setFactsForm(factsDraft(next));
        },
      );
    } catch {
      setActionState("error");
    }
  }

  const localeTag = locale === "fr" ? "fr-CA" : "en-CA";
  const navigationQuery = [
    previewEnabled ? "preview=inventory" : null,
    workspaceId ? `workspace=${encodeURIComponent(workspaceId)}` : null,
  ]
    .filter((value): value is string => value !== null)
    .join("&");
  const mediaHref = `/inventory/${inventoryUnitId}/media${
    navigationQuery ? `?${navigationQuery}` : ""
  }`;
  const vehicleTitle = detail
    ? [
        detail.vehicleFacts.modelYear,
        detail.vehicleFacts.make,
        detail.vehicleFacts.model,
        detail.vehicleFacts.trimName,
      ]
        .filter((value) => value !== null)
        .join(" ") || copy.headingFallback
    : copy.headingFallback;
  const actionMessage =
    actionState === "saved"
      ? copy.saved
      : actionState === "conflict"
        ? copy.conflict
        : actionState === "step_up"
          ? copy.stepUpMessage
          : actionState === "error"
            ? copy.commandFailed
            : null;
  const postedCosts =
    costs?.entries.filter(
      (entry) =>
        entry.entryKind === "cost" && entry.effectiveStatus === "posted",
    ) ?? [];
  const workspaceSwitchBlocked = phase === "loading" || busyAction !== null;
  const shellWorkspaces =
    workspaces.length === 0
      ? [{ id: "", name: copy.workspaceLoading }]
      : workspaceSwitchBlocked
        ? workspaces.filter((workspace) => workspace.id === workspaceId)
        : workspaces;

  return (
    <OperatorShell
      attentionCount={
        actionState === "conflict" ||
        actionState === "error" ||
        actionState === "step_up"
          ? 1
          : 0
      }
      contextLabel={
        previewEnabled
          ? copy.previewLabel
          : detail
            ? `${copy.stockLabel} · ${detail.stockNumber}`
            : copy.inventoryNavigation
      }
      copy={{
        appName: "Vynlo",
        attention: copy.statusPending,
        environment: copy.actionsHeading,
        localeLabel: copy.localeLabel,
        localeNames: copy.localeNames,
        navigationLabel: `${copy.inventoryNavigation} · Vynlo`,
        skipToContent: copy.actionsHeading,
        workspaceLabel: copy.workspaceLabel,
      }}
      current="inventory"
      locale={locale}
      mainId="inventory-operations-main"
      onWorkspaceChange={(nextWorkspaceId) => {
        if (!workspaceSwitchBlocked) chooseWorkspace(nextWorkspaceId);
      }}
      previewMode={previewEnabled ? "inventory" : null}
      selectedWorkspaceId={workspaceId}
      summary={
        phase === "loading" ? copy.loadingDescription : copy.actionsHeading
      }
      title={vehicleTitle}
      workspaces={shellWorkspaces}
    >
      <div className="inventory-operations">
        <nav
          aria-label={copy.inventoryNavigation}
          className="inventory-operations__breadcrumb"
        >
          <a
            href={
              previewEnabled ? "/inventory?preview=inventory" : "/inventory"
            }
          >
            <ArrowLeft aria-hidden="true" size={17} />
            {copy.backToInventory}
          </a>
          <a href={mediaHref}>
            <Images aria-hidden="true" size={17} />
            {copy.managePhotosAction}
          </a>
        </nav>

        {phase === "loading" ? (
          <section className="inventory-operations__state" role="status">
            <LoaderCircle
              aria-hidden="true"
              className="inventory-browser__spinner"
            />
            <div>
              <h2>{copy.loadingHeading}</h2>
              <p>{copy.loadingDescription}</p>
            </div>
          </section>
        ) : null}
        {phase === "error" ? (
          <section
            className="inventory-operations__state inventory-operations__state--error"
            role="alert"
          >
            <CircleAlert aria-hidden="true" />
            <div>
              <h2>{copy.unavailableHeading}</h2>
              <p>{copy.unavailableDescription}</p>
              <Button
                onClick={() => void loadData(workspaceId)}
                type="button"
                variant="outline"
              >
                <RefreshCw aria-hidden="true" size={17} />
                {copy.retryAction}
              </Button>
            </div>
          </section>
        ) : null}

        {phase === "ready" && detail && detailForm && factsForm ? (
          <>
            <header className="inventory-operations__identity">
              <div>
                {previewEnabled ? (
                  <p className="inventory-operations__preview">
                    {copy.previewLabel}
                  </p>
                ) : null}
                <p className="inventory-operations__stock">
                  {copy.stockLabel} · {detail.stockNumber}
                </p>
                <p className="inventory-operations__vin">
                  {detail.vehicleFacts.vin}
                </p>
              </div>
              <dl>
                <div>
                  <dt>{copy.statusLabel}</dt>
                  <dd>{statusText(copy, detail.canonicalStatus)}</dd>
                </div>
                <div>
                  <dt>{copy.stateLabel}</dt>
                  <dd>{detail.workflowStateKey}</dd>
                </div>
                <div>
                  <dt>{copy.versionLabel}</dt>
                  <dd>{detail.aggregateVersion}</dd>
                </div>
              </dl>
            </header>

            {actionMessage ? (
              <div
                className="inventory-operations__notice"
                data-state={actionState}
                role={
                  actionState === "error" || actionState === "conflict"
                    ? "alert"
                    : "status"
                }
              >
                <p>{actionMessage}</p>
                {actionState === "conflict" ? (
                  <Button
                    onClick={() => void loadData(workspaceId)}
                    type="button"
                    variant="outline"
                  >
                    <RotateCcw aria-hidden="true" size={17} />
                    {copy.reloadAction}
                  </Button>
                ) : null}
              </div>
            ) : null}

            <div className="inventory-operations__layout">
              <div className="inventory-operations__primary">
                <section
                  aria-labelledby="inventory-details-heading"
                  className="inventory-operations__section"
                >
                  <header>
                    <h2 id="inventory-details-heading">
                      {copy.detailsHeading}
                    </h2>
                  </header>
                  <form onSubmit={submitDetails}>
                    <div className="inventory-operations__form-grid">
                      <label>
                        <span>{copy.acquisitionDateLabel}</span>
                        <Input
                          disabled={!detail.capabilities.canUpdateDetails}
                          onChange={(event) =>
                            setDetailForm({
                              ...detailForm,
                              acquisitionDate: event.target.value,
                            })
                          }
                          type="date"
                          value={detailForm.acquisitionDate}
                        />
                      </label>
                      <label>
                        <span>{copy.conditionLabel}</span>
                        <Input
                          disabled={!detail.capabilities.canUpdateDetails}
                          maxLength={100}
                          onChange={(event) =>
                            setDetailForm({
                              ...detailForm,
                              conditionKey: event.target.value,
                            })
                          }
                          value={detailForm.conditionKey}
                        />
                      </label>
                      <label>
                        <span>{copy.advertisedPriceLabel}</span>
                        <Input
                          disabled={!detail.capabilities.canUpdateDetails}
                          inputMode="decimal"
                          onChange={(event) =>
                            setDetailForm({
                              ...detailForm,
                              advertisedPrice: event.target.value,
                            })
                          }
                          value={detailForm.advertisedPrice}
                        />
                      </label>
                      <label>
                        <span>{copy.expectedSalePriceLabel}</span>
                        <Input
                          disabled={!detail.capabilities.canUpdateDetails}
                          inputMode="decimal"
                          onChange={(event) =>
                            setDetailForm({
                              ...detailForm,
                              expectedSalePrice: event.target.value,
                            })
                          }
                          value={detailForm.expectedSalePrice}
                        />
                      </label>
                      <label>
                        <span>{copy.odometerLabel}</span>
                        <Input
                          disabled={!detail.capabilities.canUpdateDetails}
                          inputMode="numeric"
                          onChange={(event) =>
                            setDetailForm({
                              ...detailForm,
                              odometerValue: event.target.value,
                            })
                          }
                          value={detailForm.odometerValue}
                        />
                      </label>
                      <label>
                        <span>{copy.odometerUnitLabel}</span>
                        <NativeSelect
                          disabled={!detail.capabilities.canUpdateDetails}
                          onChange={(event) =>
                            setDetailForm({
                              ...detailForm,
                              odometerUnit: event.target.value as "km" | "mi",
                            })
                          }
                          value={detailForm.odometerUnit}
                        >
                          <option value="km">km</option>
                          <option value="mi">mi</option>
                        </NativeSelect>
                      </label>
                    </div>
                    <label>
                      <span>{copy.publicNotesLabel}</span>
                      <Textarea
                        disabled={!detail.capabilities.canUpdateDetails}
                        maxLength={4000}
                        onChange={(event) =>
                          setDetailForm({
                            ...detailForm,
                            publicNotes: event.target.value,
                          })
                        }
                        rows={3}
                        value={detailForm.publicNotes}
                      />
                    </label>
                    {detail.capabilities.canReadInternal ? (
                      <label>
                        <span>{copy.internalNotesLabel}</span>
                        <Textarea
                          disabled={!detail.capabilities.canUpdateInternal}
                          maxLength={8000}
                          onChange={(event) =>
                            setDetailForm({
                              ...detailForm,
                              internalNotes: event.target.value,
                            })
                          }
                          rows={3}
                          value={detailForm.internalNotes}
                        />
                      </label>
                    ) : null}
                    {detail.capabilities.canUpdateDetails ? (
                      <Button disabled={busyAction !== null} type="submit">
                        <Save aria-hidden="true" size={17} />
                        {busyAction === "details"
                          ? copy.saving
                          : copy.saveDetailsAction}
                      </Button>
                    ) : null}
                  </form>
                </section>

                <section
                  aria-labelledby="inventory-location-heading"
                  className="inventory-operations__section"
                >
                  <header>
                    <h2 id="inventory-location-heading">
                      {copy.locationHeading}
                    </h2>
                    <p>{detail.location?.name ?? copy.noLocation}</p>
                  </header>
                  {detail.capabilities.canTransferLocation ? (
                    <form onSubmit={submitTransfer}>
                      <label>
                        <span>{copy.locationLabel}</span>
                        <NativeSelect
                          onChange={(event) =>
                            setTargetLocationId(event.target.value)
                          }
                          required
                          value={targetLocationId}
                        >
                          {locations.map((location) => (
                            <option key={location.id} value={location.id}>
                              {location.name}
                            </option>
                          ))}
                        </NativeSelect>
                      </label>
                      <label>
                        <span>{copy.reasonLabel}</span>
                        <Textarea
                          maxLength={2000}
                          onChange={(event) =>
                            setTransferReason(event.target.value)
                          }
                          required
                          rows={2}
                          value={transferReason}
                        />
                      </label>
                      <Button
                        disabled={busyAction !== null || !targetLocationId}
                        type="submit"
                      >
                        <ArrowRightLeft aria-hidden="true" size={17} />
                        {busyAction === "location"
                          ? copy.saving
                          : copy.transferAction}
                      </Button>
                    </form>
                  ) : null}
                </section>

                <section
                  aria-labelledby="inventory-workflow-heading"
                  className="inventory-operations__section"
                >
                  <header>
                    <h2 id="inventory-workflow-heading">
                      {copy.transitionHeading}
                    </h2>
                    <p>{detail.workflowConfigurationVersion}</p>
                  </header>
                  {detail.capabilities.canTransitionWorkflow &&
                  detail.allowedTransitions.length > 0 ? (
                    <form onSubmit={submitTransition}>
                      <label>
                        <span>{copy.transitionLabel}</span>
                        <NativeSelect
                          onChange={(event) =>
                            setTransitionKey(event.target.value)
                          }
                          required
                          value={transitionKey}
                        >
                          <option value="">{copy.allTransitions}</option>
                          {detail.allowedTransitions.map((transition) => (
                            <option key={transition.key} value={transition.key}>
                              {localizedLabel(
                                transition.labels,
                                locale,
                                transition.toStateKey,
                              )}
                            </option>
                          ))}
                        </NativeSelect>
                      </label>
                      <label>
                        <span>{copy.reasonLabel}</span>
                        <Textarea
                          maxLength={2000}
                          onChange={(event) =>
                            setTransitionReason(event.target.value)
                          }
                          rows={2}
                          value={transitionReason}
                        />
                      </label>
                      <Button
                        disabled={busyAction !== null || !transitionKey}
                        type="submit"
                      >
                        {busyAction === "transition"
                          ? copy.saving
                          : copy.transitionAction}
                      </Button>
                    </form>
                  ) : null}
                </section>

                <section
                  aria-labelledby="inventory-cost-heading"
                  className="inventory-operations__section"
                >
                  <header>
                    <h2 id="inventory-cost-heading">{copy.costHeading}</h2>
                  </header>
                  {!detail.capabilities.canReadCosts || !costs ? (
                    <p>{copy.costsUnavailable}</p>
                  ) : (
                    <>
                      <dl className="inventory-operations__metrics">
                        <div>
                          <dt>{copy.postedCostLabel}</dt>
                          <dd>
                            {formatMinorMoney(
                              costs.postedCostMinor,
                              costs.currencyCode,
                              localeTag,
                            )}
                          </dd>
                        </div>
                        <div>
                          <dt>{copy.estimatedGrossLabel}</dt>
                          <dd>
                            {costs.estimatedGrossMinor === null
                              ? "—"
                              : formatMinorMoney(
                                  costs.estimatedGrossMinor,
                                  costs.currencyCode,
                                  localeTag,
                                )}
                          </dd>
                        </div>
                      </dl>
                      {costs.canCreate ? (
                        <form onSubmit={submitCost}>
                          <div className="inventory-operations__form-grid">
                            <label>
                              <span>{copy.categoryLabel}</span>
                              <NativeSelect
                                onChange={(event) =>
                                  setCostCategoryId(event.target.value)
                                }
                                required
                                value={costCategoryId}
                              >
                                {costs.categories.map((category) => (
                                  <option key={category.id} value={category.id}>
                                    {localizedLabel(
                                      category.labels,
                                      locale,
                                      category.key,
                                    )}
                                  </option>
                                ))}
                              </NativeSelect>
                            </label>
                            <label>
                              <span>{copy.costAmountLabel}</span>
                              <Input
                                inputMode="decimal"
                                onChange={(event) =>
                                  setCostAmount(event.target.value)
                                }
                                required
                                value={costAmount}
                              />
                            </label>
                            <label>
                              <span>{copy.costDateLabel}</span>
                              <Input
                                onChange={(event) =>
                                  setCostDate(event.target.value)
                                }
                                required
                                type="date"
                                value={costDate}
                              />
                            </label>
                          </div>
                          <label>
                            <span>{copy.costDescriptionLabel}</span>
                            <Textarea
                              maxLength={2000}
                              onChange={(event) =>
                                setCostDescription(event.target.value)
                              }
                              rows={2}
                              value={costDescription}
                            />
                          </label>
                          <Button disabled={busyAction !== null} type="submit">
                            {busyAction === "cost"
                              ? copy.saving
                              : copy.createCostAction}
                          </Button>
                        </form>
                      ) : null}
                      <div
                        className="inventory-operations__ledger"
                        role="region"
                        aria-label={copy.costEntriesLabel}
                        tabIndex={0}
                      >
                        {costs.entries.length === 0 ? (
                          <p>{copy.emptyCosts}</p>
                        ) : (
                          costs.entries.map((entry) => (
                            <article
                              key={entry.id}
                              data-status={entry.effectiveStatus}
                            >
                              <div>
                                <strong>
                                  {localizedLabel(
                                    entry.categoryLabels,
                                    locale,
                                    entry.categoryKey,
                                  )}
                                </strong>
                                <span>{entry.incurredOn}</span>
                              </div>
                              <p>
                                {formatMinorMoney(
                                  entry.amountMinor,
                                  entry.currencyCode,
                                  localeTag,
                                )}
                              </p>
                              <small>{entry.description}</small>
                            </article>
                          ))
                        )}
                      </div>
                      {costs.canReverse && postedCosts.length > 0 ? (
                        <form
                          aria-labelledby="inventory-reversal-heading"
                          onSubmit={submitReversal}
                        >
                          <h3 id="inventory-reversal-heading">
                            {copy.reversalHeading}
                          </h3>
                          {!costs.hasRecentStrongAuthentication ? (
                            <p className="inventory-operations__step-up">
                              {copy.stepUpMessage}
                            </p>
                          ) : null}
                          <label>
                            <span>{copy.reversalEntryLabel}</span>
                            <NativeSelect
                              onChange={(event) =>
                                setReversalCostId(event.target.value)
                              }
                              required
                              value={reversalCostId}
                            >
                              {postedCosts.map((entry) => (
                                <option key={entry.id} value={entry.id}>
                                  {localizedLabel(
                                    entry.categoryLabels,
                                    locale,
                                    entry.categoryKey,
                                  )}{" "}
                                  ·{" "}
                                  {formatMinorMoney(
                                    entry.amountMinor,
                                    entry.currencyCode,
                                    localeTag,
                                  )}
                                </option>
                              ))}
                            </NativeSelect>
                          </label>
                          <label>
                            <span>{copy.reversalDateLabel}</span>
                            <Input
                              onChange={(event) =>
                                setReversalDate(event.target.value)
                              }
                              required
                              type="date"
                              value={reversalDate}
                            />
                          </label>
                          <label>
                            <span>{copy.reasonLabel}</span>
                            <Textarea
                              maxLength={2000}
                              onChange={(event) =>
                                setReversalReason(event.target.value)
                              }
                              required
                              rows={2}
                              value={reversalReason}
                            />
                          </label>
                          <Button
                            disabled={
                              busyAction !== null ||
                              !costs.hasRecentStrongAuthentication
                            }
                            type="submit"
                          >
                            {busyAction === "reversal"
                              ? copy.saving
                              : copy.reversalAction}
                          </Button>
                        </form>
                      ) : null}
                    </>
                  )}
                </section>
              </div>

              <aside
                className="inventory-operations__facts"
                aria-labelledby="inventory-facts-heading"
              >
                <header>
                  <h2 id="inventory-facts-heading">{copy.factsHeading}</h2>
                  <p>{copy.factsIntroduction}</p>
                </header>
                <dl className="inventory-operations__facts-summary">
                  <div>
                    <dt>{copy.vinLabel}</dt>
                    <dd>{detail.vehicleFacts.vin}</dd>
                  </div>
                  <div>
                    <dt>{copy.versionLabel}</dt>
                    <dd>{detail.vehicleFacts.factsVersion}</dd>
                  </div>
                </dl>
                {detail.capabilities.canOverrideFacts ? (
                  <form onSubmit={submitFacts}>
                    {!detail.capabilities.hasRecentStrongAuthentication ? (
                      <p className="inventory-operations__step-up">
                        {copy.stepUpMessage}
                      </p>
                    ) : null}
                    <div className="inventory-operations__form-grid">
                      <label>
                        <span>{copy.modelYearLabel}</span>
                        <Input
                          inputMode="numeric"
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              modelYear: event.target.value,
                            })
                          }
                          value={factsForm.modelYear}
                        />
                      </label>
                      <label>
                        <span>{copy.makeLabel}</span>
                        <Input
                          maxLength={100}
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              make: event.target.value,
                            })
                          }
                          value={factsForm.make}
                        />
                      </label>
                      <label>
                        <span>{copy.modelLabel}</span>
                        <Input
                          maxLength={100}
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              model: event.target.value,
                            })
                          }
                          value={factsForm.model}
                        />
                      </label>
                      <label>
                        <span>{copy.trimLabel}</span>
                        <Input
                          maxLength={200}
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              trimName: event.target.value,
                            })
                          }
                          value={factsForm.trimName}
                        />
                      </label>
                      <label>
                        <span>{copy.bodyTypeLabel}</span>
                        <Input
                          maxLength={200}
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              bodyType: event.target.value,
                            })
                          }
                          value={factsForm.bodyType}
                        />
                      </label>
                      <label>
                        <span>{copy.drivetrainLabel}</span>
                        <Input
                          maxLength={100}
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              drivetrain: event.target.value,
                            })
                          }
                          value={factsForm.drivetrain}
                        />
                      </label>
                      <label>
                        <span>{copy.engineLitersLabel}</span>
                        <Input
                          inputMode="decimal"
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              engineLiters: event.target.value,
                            })
                          }
                          value={factsForm.engineLiters}
                        />
                      </label>
                      <label>
                        <span>{copy.cylindersLabel}</span>
                        <Input
                          inputMode="numeric"
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              cylinders: event.target.value,
                            })
                          }
                          value={factsForm.cylinders}
                        />
                      </label>
                      <label>
                        <span>{copy.fuelTypeLabel}</span>
                        <Input
                          maxLength={100}
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              fuelType: event.target.value,
                            })
                          }
                          value={factsForm.fuelType}
                        />
                      </label>
                      <label>
                        <span>{copy.horsepowerLabel}</span>
                        <Input
                          inputMode="numeric"
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              horsepower: event.target.value,
                            })
                          }
                          value={factsForm.horsepower}
                        />
                      </label>
                      <label>
                        <span>{copy.transmissionLabel}</span>
                        <Input
                          maxLength={200}
                          onChange={(event) =>
                            setFactsForm({
                              ...factsForm,
                              transmission: event.target.value,
                            })
                          }
                          value={factsForm.transmission}
                        />
                      </label>
                    </div>
                    <label>
                      <span>{copy.reasonLabel}</span>
                      <Textarea
                        maxLength={2000}
                        onChange={(event) =>
                          setFactsForm({
                            ...factsForm,
                            reason: event.target.value,
                          })
                        }
                        required
                        rows={3}
                        value={factsForm.reason}
                      />
                    </label>
                    <Button
                      disabled={
                        busyAction !== null ||
                        !detail.capabilities.hasRecentStrongAuthentication
                      }
                      type="submit"
                    >
                      {busyAction === "facts"
                        ? copy.saving
                        : copy.updateFactsAction}
                    </Button>
                  </form>
                ) : (
                  <dl className="inventory-operations__facts-summary">
                    <div>
                      <dt>{copy.makeLabel}</dt>
                      <dd>{detail.vehicleFacts.make ?? "—"}</dd>
                    </div>
                    <div>
                      <dt>{copy.modelLabel}</dt>
                      <dd>{detail.vehicleFacts.model ?? "—"}</dd>
                    </div>
                  </dl>
                )}
              </aside>
            </div>
          </>
        ) : null}
      </div>
    </OperatorShell>
  );
}
