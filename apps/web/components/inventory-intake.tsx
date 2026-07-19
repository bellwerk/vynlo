"use client";

import { Button } from "@vynlo/ui-web/components/button";
import { Checkbox } from "@vynlo/ui-web/components/checkbox";
import { Input } from "@vynlo/ui-web/components/input";
import { NativeSelect } from "@vynlo/ui-web/components/native-select";
import { Textarea } from "@vynlo/ui-web/components/textarea";
import {
  ArrowLeft,
  Check,
  CircleAlert,
  LoaderCircle,
  RotateCcw,
} from "lucide-react";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import type { InventoryIntakeCopy } from "../i18n/inventory-intake-messages";
import type { Locale } from "../i18n/messages";
import { parseMajorMoneyToMinor } from "../lib/inventory-money";
import { getBrowserSupabase } from "../lib/supabase-browser";
import { OperatorShell } from "./operator-shell";
import { VehiclePhotoUpload } from "./vehicle-photo-upload";

type CanonicalStatus = "active" | "archived" | "closed" | "draft" | "pending";
type DuplicateDecision =
  | "override_open_duplicate"
  | "reacquire_existing_vehicle"
  | "reuse_existing_vehicle";
type JobStatus =
  | "cancelled"
  | "consumed"
  | "dead_letter"
  | "queued"
  | "retry_wait"
  | "running"
  | "succeeded";
type Step = 1 | 2 | 3;

interface WorkspaceOption {
  readonly currencyCode: string;
  readonly id: string;
  readonly name: string;
  readonly odometerUnit: "km" | "mi";
}

interface StockDefinition {
  readonly id: string;
  readonly key: string;
  readonly numericWidth: number;
  readonly prefix: string;
  readonly version: number;
}

interface IntakeLocation {
  readonly id: string;
  readonly name: string;
}

interface InventoryConditionDefinition {
  readonly key: string;
  readonly labels: Readonly<Record<string, string>>;
}

interface DuplicateCandidate {
  readonly id: string;
  readonly inventoryStatus: CanonicalStatus | null;
  readonly inventoryUnitId: string | null;
  readonly kind: "historical_inventory" | "open_inventory" | "vehicle_only";
  readonly stockNumber: string | null;
  readonly vehicleId: string;
}

interface VehicleSuggestions {
  readonly bodyType: string | null;
  readonly cylinders: number | null;
  readonly drivetrain: string | null;
  readonly engineLiters: string | null;
  readonly fuelType: string | null;
  readonly horsepower: number | null;
  readonly make: string | null;
  readonly model: string | null;
  readonly modelYear: number | null;
  readonly transmission: string | null;
  readonly trimName: string | null;
}

interface DecodeStatus {
  readonly aggregateVersion: number;
  readonly duplicateCandidates: readonly DuplicateCandidate[];
  readonly duplicateReviewApproved: boolean;
  readonly duplicateReviewRecorded: boolean;
  readonly job: Readonly<{
    attemptCount: number;
    maximumAttempts: number;
    retryable: boolean;
    reviewRequired: boolean;
  }>;
  readonly status: JobStatus;
  readonly statusLoaded: boolean;
  readonly suggestions: VehicleSuggestions | null;
  readonly vin: string;
  readonly vinDecodeRequestId: string;
  readonly vinDecodeResultId: string | null;
  readonly warnings: readonly string[];
}

interface VehicleFields {
  readonly bodyType: string;
  readonly cylinders: string;
  readonly drivetrain: string;
  readonly engineLiters: string;
  readonly fuelType: string;
  readonly horsepower: string;
  readonly make: string;
  readonly model: string;
  readonly modelYear: string;
  readonly transmission: string;
  readonly trimName: string;
}

function VehicleFactFields({
  copy,
  fields,
  onFieldChange,
}: Readonly<{
  copy: InventoryIntakeCopy;
  fields: VehicleFields;
  onFieldChange: (field: keyof VehicleFields, value: string) => void;
}>) {
  return (
    <div className="inventory-intake__vehicle-fields">
      <label>
        <span>{copy.modelYearLabel}</span>
        <Input
          inputMode="numeric"
          max="2200"
          min="1886"
          onChange={(event) => onFieldChange("modelYear", event.target.value)}
          required
          type="number"
          value={fields.modelYear}
        />
      </label>
      <label>
        <span>{copy.makeLabel}</span>
        <Input
          maxLength={100}
          onChange={(event) => onFieldChange("make", event.target.value)}
          required
          value={fields.make}
        />
      </label>
      <label>
        <span>{copy.modelLabel}</span>
        <Input
          maxLength={100}
          onChange={(event) => onFieldChange("model", event.target.value)}
          required
          value={fields.model}
        />
      </label>
      <label>
        <span>{copy.trimLabel}</span>
        <Input
          maxLength={200}
          onChange={(event) => onFieldChange("trimName", event.target.value)}
          value={fields.trimName}
        />
      </label>
      <label>
        <span>{copy.bodyTypeLabel}</span>
        <Input
          maxLength={200}
          onChange={(event) => onFieldChange("bodyType", event.target.value)}
          value={fields.bodyType}
        />
      </label>
      <label>
        <span>{copy.drivetrainLabel}</span>
        <Input
          maxLength={100}
          onChange={(event) => onFieldChange("drivetrain", event.target.value)}
          value={fields.drivetrain}
        />
      </label>
      <label>
        <span>{copy.transmissionLabel}</span>
        <Input
          maxLength={200}
          onChange={(event) =>
            onFieldChange("transmission", event.target.value)
          }
          value={fields.transmission}
        />
      </label>
      <label>
        <span>{copy.fuelTypeLabel}</span>
        <Input
          maxLength={100}
          onChange={(event) => onFieldChange("fuelType", event.target.value)}
          value={fields.fuelType}
        />
      </label>
      <label>
        <span>{copy.engineLabel}</span>
        <Input
          inputMode="decimal"
          maxLength={6}
          onChange={(event) =>
            onFieldChange("engineLiters", event.target.value)
          }
          value={fields.engineLiters}
        />
      </label>
      <label>
        <span>{copy.cylindersLabel}</span>
        <Input
          inputMode="numeric"
          max="64"
          min="1"
          onChange={(event) => onFieldChange("cylinders", event.target.value)}
          type="number"
          value={fields.cylinders}
        />
      </label>
      <label>
        <span>{copy.horsepowerLabel}</span>
        <Input
          inputMode="numeric"
          max="10000"
          min="1"
          onChange={(event) => onFieldChange("horsepower", event.target.value)}
          type="number"
          value={fields.horsepower}
        />
      </label>
    </div>
  );
}

function optionalIntegerFact(
  value: string,
  minimum: number,
  maximum: number,
): number | null {
  const normalized = value.trim();
  if (!normalized) return null;
  if (!/^\d+$/u.test(normalized)) {
    throw new TypeError("invalid_vehicle_facts");
  }
  const parsed = Number(normalized);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new TypeError("invalid_vehicle_facts");
  }
  return parsed;
}

function confirmedVehicleFacts(fields: VehicleFields) {
  const engineLiters = fields.engineLiters.trim();
  if (
    engineLiters &&
    (!/^\d{1,2}(?:\.\d{1,3})?$/u.test(engineLiters) ||
      Number(engineLiters) < 0.001 ||
      Number(engineLiters) > 99.999)
  ) {
    throw new TypeError("invalid_vehicle_facts");
  }
  return {
    bodyType: fields.bodyType.trim() || null,
    cylinders: optionalIntegerFact(fields.cylinders, 1, 64),
    drivetrain: fields.drivetrain.trim() || null,
    engineLiters: engineLiters || null,
    fuelType: fields.fuelType.trim() || null,
    horsepower: optionalIntegerFact(fields.horsepower, 1, 10_000),
    make: fields.make.trim() || null,
    model: fields.model.trim() || null,
    modelYear: optionalIntegerFact(fields.modelYear, 1886, 2200),
    transmission: fields.transmission.trim() || null,
    trimName: fields.trimName.trim() || null,
  } as const;
}

const VIN_PATTERN = /^[A-HJ-NPR-Z0-9]{17}$/u;
const PREVIEW_DUPLICATE_VIN = "2SAMP34EFGH567890";
const PREVIEW_DUPLICATE_FAILURE_VIN = "3SAMP34EFGH567890";
const PREVIEW_FAILURE_VIN = "9FALR23ABCD456789";
const PREVIEW_REQUEST_ID = "00000000-0000-4000-8000-000000000301";
const PREVIEW_RESULT_ID = "00000000-0000-4000-8000-000000000304";
const PREVIEW_INVENTORY_UNIT_ID = "00000000-0000-4000-8000-000000000305";
const PREVIEW_LOCATION_ID = "00000000-0000-4000-8000-000000000306";
const PREVIEW_VEHICLE_ID = "00000000-0000-4000-8000-000000000307";

const previewWorkspace: WorkspaceOption = Object.freeze({
  currencyCode: "CAD",
  id: "00000000-0000-4000-8000-000000000201",
  name: "Sample workspace",
  odometerUnit: "km",
});

const previewStockDefinitions: readonly StockDefinition[] = Object.freeze([
  {
    id: "00000000-0000-4000-8000-000000000302",
    key: "synthetic.default",
    numericWidth: 5,
    prefix: "SYN-",
    version: 1,
  },
]);

const previewLocations: readonly IntakeLocation[] = Object.freeze([
  { id: PREVIEW_LOCATION_ID, name: "Main showroom" },
]);

const previewConditionDefinitions: readonly InventoryConditionDefinition[] =
  Object.freeze([
    {
      key: "used.ready",
      labels: { en: "Used - ready", fr: "Occasion - prêt" },
    },
  ]);

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function nullableString(value: unknown): string | null | undefined {
  return value === null ? null : typeof value === "string" ? value : undefined;
}

function isJobStatus(value: unknown): value is JobStatus {
  return [
    "cancelled",
    "consumed",
    "dead_letter",
    "queued",
    "retry_wait",
    "running",
    "succeeded",
  ].includes(value as JobStatus);
}

function isCanonicalStatus(value: unknown): value is CanonicalStatus {
  return ["active", "archived", "closed", "draft", "pending"].includes(
    value as CanonicalStatus,
  );
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
      typeof workspace.name === "string" &&
      typeof workspace.default_currency === "string" &&
      (workspace.odometer_unit === "km" || workspace.odometer_unit === "mi")
      ? [
          {
            currencyCode: workspace.default_currency,
            id: workspace.id,
            name: workspace.name,
            odometerUnit: workspace.odometer_unit,
          },
        ]
      : [];
  });
}

function parseStockDefinitions(value: unknown): readonly StockDefinition[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const definition = record(item);
    return typeof definition?.id === "string" &&
      typeof definition.key === "string" &&
      typeof definition.prefix === "string" &&
      typeof definition.numeric_width === "number" &&
      typeof definition.version === "number"
      ? [
          {
            id: definition.id,
            key: definition.key,
            numericWidth: definition.numeric_width,
            prefix: definition.prefix,
            version: definition.version,
          },
        ]
      : [];
  });
}

function parseLocations(value: unknown): readonly IntakeLocation[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const location = record(item);
    return typeof location?.id === "string" && typeof location.name === "string"
      ? [{ id: location.id, name: location.name }]
      : [];
  });
}

function parseConditionDefinitions(
  value: unknown,
): readonly InventoryConditionDefinition[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const condition = record(item);
    const labels = record(condition?.labels);
    return typeof condition?.key === "string" &&
      labels &&
      Object.values(labels).every((label) => typeof label === "string")
      ? [{ key: condition.key, labels: labels as Record<string, string> }]
      : [];
  });
}

function parseDuplicateCandidates(
  value: unknown,
): readonly DuplicateCandidate[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const candidate = record(item);
    const inventoryStatus = candidate?.inventoryStatus;
    const inventoryUnitId = candidate?.inventoryUnitId;
    return typeof candidate?.id === "string" &&
      (inventoryUnitId === null || typeof inventoryUnitId === "string") &&
      ["historical_inventory", "open_inventory", "vehicle_only"].includes(
        String(candidate.kind),
      ) &&
      (inventoryStatus === null || isCanonicalStatus(inventoryStatus)) &&
      (candidate.stockNumber === null ||
        typeof candidate.stockNumber === "string") &&
      typeof candidate.vehicleId === "string"
      ? [
          {
            id: candidate.id,
            inventoryStatus: inventoryStatus as CanonicalStatus | null,
            inventoryUnitId: inventoryUnitId as string | null,
            kind: candidate.kind as DuplicateCandidate["kind"],
            stockNumber: candidate.stockNumber as string | null,
            vehicleId: candidate.vehicleId,
          },
        ]
      : [];
  });
}

function parseSuggestions(
  value: unknown,
): VehicleSuggestions | null | undefined {
  if (value === null) return null;
  const suggestions = record(value);
  if (!suggestions) return undefined;
  const bodyType = nullableString(suggestions.bodyType);
  const drivetrain = nullableString(suggestions.drivetrain);
  const engineLiters = nullableString(suggestions.engineLiters);
  const fuelType = nullableString(suggestions.fuelType);
  const cylinders = suggestions.cylinders;
  const horsepower = suggestions.horsepower;
  const make = nullableString(suggestions.make);
  const model = nullableString(suggestions.model);
  const transmission = nullableString(suggestions.transmission);
  const trimName = nullableString(suggestions.trimName);
  const modelYear = suggestions.modelYear;
  if (
    [
      bodyType,
      drivetrain,
      engineLiters,
      fuelType,
      make,
      model,
      transmission,
      trimName,
    ].some((field) => field === undefined) ||
    (cylinders !== null &&
      (typeof cylinders !== "number" || !Number.isInteger(cylinders))) ||
    (horsepower !== null &&
      (typeof horsepower !== "number" || !Number.isInteger(horsepower))) ||
    (modelYear !== null &&
      (typeof modelYear !== "number" || !Number.isInteger(modelYear)))
  ) {
    return undefined;
  }
  return {
    bodyType: bodyType!,
    cylinders: cylinders as number | null,
    drivetrain: drivetrain!,
    engineLiters: engineLiters!,
    fuelType: fuelType!,
    horsepower: horsepower as number | null,
    make: make!,
    model: model!,
    modelYear: modelYear as number | null,
    transmission: transmission!,
    trimName: trimName!,
  };
}

function parseDecodeStatus(value: unknown): DecodeStatus {
  const envelope = record(value);
  const data = record(envelope?.data);
  const job = record(data?.job);
  const provider = data?.provider === null ? null : record(data?.provider);
  const providerWarnings = provider?.warnings;
  const duplicateReview =
    data?.duplicateReview === null ? null : record(data?.duplicateReview);
  const suggestions = parseSuggestions(data?.suggestions);
  const candidates = parseDuplicateCandidates(data?.duplicateCandidates);
  if (
    !data ||
    !job ||
    typeof data.aggregateVersion !== "number" ||
    !Number.isSafeInteger(data.aggregateVersion) ||
    data.aggregateVersion < 1 ||
    typeof data.vin !== "string" ||
    !VIN_PATTERN.test(data.vin) ||
    typeof data.vinDecodeRequestId !== "string" ||
    !isJobStatus(data.status) ||
    typeof job.attemptCount !== "number" ||
    !Number.isInteger(job.attemptCount) ||
    typeof job.maximumAttempts !== "number" ||
    !Number.isInteger(job.maximumAttempts) ||
    typeof job.retryable !== "boolean" ||
    typeof job.reviewRequired !== "boolean" ||
    suggestions === undefined ||
    !Array.isArray(data.duplicateCandidates) ||
    candidates.length !== data.duplicateCandidates.length ||
    (duplicateReview !== null &&
      ![
        "override_open_duplicate",
        "reacquire_existing_vehicle",
        "reuse_existing_vehicle",
      ].includes(String(duplicateReview.decision))) ||
    (provider !== null &&
      (!Array.isArray(providerWarnings) ||
        typeof provider.rawResultReference !== "string")) ||
    (data.status === "succeeded" && (suggestions === null || provider === null))
  ) {
    throw new TypeError("invalid_vin_status_response");
  }
  const warnings = Array.isArray(providerWarnings) ? providerWarnings : [];
  if (!warnings.every((warning) => typeof warning === "string")) {
    throw new TypeError("invalid_vin_status_response");
  }
  return {
    aggregateVersion: data.aggregateVersion,
    duplicateCandidates: candidates,
    duplicateReviewApproved: duplicateReview !== null,
    duplicateReviewRecorded: data.duplicateReview !== null,
    job: {
      attemptCount: job.attemptCount,
      maximumAttempts: job.maximumAttempts,
      retryable: job.retryable,
      reviewRequired: job.reviewRequired,
    },
    status: data.status,
    statusLoaded: true,
    suggestions,
    vin: data.vin,
    vinDecodeRequestId: data.vinDecodeRequestId,
    vinDecodeResultId:
      provider === null ? null : (provider.rawResultReference as string),
    warnings: warnings as readonly string[],
  };
}

function commandData(value: unknown): Record<string, unknown> {
  const data = record(record(value)?.data);
  if (!data) throw new TypeError("invalid_command_response");
  return data;
}

function pendingDecodeStatus(
  vin: string,
  vinDecodeRequestId: string,
  status: JobStatus,
  aggregateVersion: number,
): DecodeStatus {
  return {
    aggregateVersion,
    duplicateCandidates: [],
    duplicateReviewApproved: false,
    duplicateReviewRecorded: false,
    job: {
      attemptCount: 0,
      maximumAttempts: 5,
      retryable: false,
      reviewRequired: false,
    },
    status,
    statusLoaded: false,
    suggestions: null,
    vin,
    vinDecodeRequestId,
    vinDecodeResultId: null,
    warnings: [],
  };
}

function previewCompletedStatus(vin: string): DecodeStatus {
  const duplicate =
    vin === PREVIEW_DUPLICATE_VIN || vin === PREVIEW_DUPLICATE_FAILURE_VIN;
  return {
    aggregateVersion: 3,
    duplicateCandidates: duplicate
      ? [
          {
            id: "00000000-0000-4000-8000-000000000303",
            inventoryStatus: "active",
            inventoryUnitId: PREVIEW_INVENTORY_UNIT_ID,
            kind: "open_inventory",
            stockNumber: "SYN-00120",
            vehicleId: PREVIEW_VEHICLE_ID,
          },
        ]
      : [],
    duplicateReviewRecorded: false,
    duplicateReviewApproved: false,
    job: {
      attemptCount: 1,
      maximumAttempts: 5,
      retryable: false,
      reviewRequired: duplicate,
    },
    status: "succeeded",
    statusLoaded: true,
    suggestions: duplicate
      ? {
          bodyType: "Sport utility vehicle",
          cylinders: 4,
          drivetrain: "All-wheel drive",
          engineLiters: "2.5",
          fuelType: "Gasoline",
          horsepower: 203,
          make: "Toyota",
          model: "RAV4",
          modelYear: 2023,
          transmission: "Automatic",
          trimName: "XLE",
        }
      : {
          bodyType: "Sport utility vehicle",
          cylinders: 4,
          drivetrain: "All-wheel drive",
          engineLiters: "2.0",
          fuelType: "Gasoline",
          horsepower: 247,
          make: "Volvo",
          model: "XC60",
          modelYear: 2024,
          transmission: "Automatic",
          trimName: "Plus",
        },
    vin,
    vinDecodeRequestId: PREVIEW_REQUEST_ID,
    vinDecodeResultId: PREVIEW_RESULT_ID,
    warnings: ["Verify equipment and trim against the vehicle paperwork."],
  };
}

function statusLabel(copy: InventoryIntakeCopy, status: JobStatus): string {
  switch (status) {
    case "cancelled":
      return copy.cancelledStatus;
    case "consumed":
      return copy.consumedStatus;
    case "dead_letter":
      return copy.deadLetterStatus;
    case "queued":
      return copy.queuedStatus;
    case "retry_wait":
      return copy.retryWaitStatus;
    case "running":
      return copy.runningStatus;
    case "succeeded":
      return copy.succeededStatus;
  }
}

function candidateKindLabel(
  copy: InventoryIntakeCopy,
  kind: DuplicateCandidate["kind"],
): string {
  switch (kind) {
    case "historical_inventory":
      return copy.candidateHistorical;
    case "open_inventory":
      return copy.candidateOpen;
    case "vehicle_only":
      return copy.candidateVehicle;
  }
}

function inventoryStatusLabel(
  copy: InventoryIntakeCopy,
  status: CanonicalStatus,
): string {
  switch (status) {
    case "active":
      return copy.activeStatus;
    case "archived":
      return copy.archivedStatus;
    case "closed":
      return copy.closedStatus;
    case "draft":
      return copy.draftStatus;
    case "pending":
      return copy.pendingStatus;
  }
}

function requiredDuplicateDecision(
  candidates: readonly DuplicateCandidate[],
): DuplicateDecision | null {
  if (candidates.some((candidate) => candidate.kind === "open_inventory")) {
    return "override_open_duplicate";
  }
  if (
    candidates.some((candidate) => candidate.kind === "historical_inventory")
  ) {
    return "reacquire_existing_vehicle";
  }
  return candidates.some((candidate) => candidate.kind === "vehicle_only")
    ? "reuse_existing_vehicle"
    : null;
}

function decisionLabel(
  copy: InventoryIntakeCopy,
  decision: DuplicateDecision,
): string {
  switch (decision) {
    case "override_open_duplicate":
      return copy.overrideDecision;
    case "reacquire_existing_vehicle":
      return copy.reacquireDecision;
    case "reuse_existing_vehicle":
      return copy.reuseDecision;
  }
}

function conditionDefinitionLabel(
  definition: InventoryConditionDefinition,
  locale: Locale,
): string {
  return (
    definition.labels[locale] ??
    definition.labels.en ??
    definition.labels.fr ??
    definition.key
  );
}

function interpolate(
  template: string,
  values: Readonly<Record<string, string | number>>,
): string {
  return Object.entries(values).reduce(
    (result, [key, value]) => result.replace(`{${key}}`, String(value)),
    template,
  );
}

function safeMoneyMinor(value: string, currencyCode: string): string | null {
  return parseMajorMoneyToMinor(value, currencyCode);
}

export function InventoryIntake({
  copy,
  locale,
  previewMode,
}: Readonly<{
  copy: InventoryIntakeCopy;
  locale: Locale;
  previewMode: boolean;
}>) {
  const router = useRouter();
  const previewEnabled =
    process.env.NODE_ENV !== "production" && previewMode === true;
  const idempotency = useRef(
    new Map<string, Readonly<{ fingerprint: string; key: string }>>(),
  );
  const activeWorkspaceId = useRef("");
  const decodeContext = useRef<
    Readonly<{ requestId: string; workspaceId: string }> | undefined
  >(undefined);
  const flowGeneration = useRef(0);
  const mappedRequestId = useRef<string | null>(null);
  const pollAbortController = useRef<AbortController | null>(null);
  const pollRequestSequence = useRef(0);
  const previewPollCount = useRef(0);
  const previewRetryCount = useRef(0);
  const pollInFlight = useRef(false);
  const intakeConfigurationRequestSequence = useRef(0);
  const [acquisitionDate, setAcquisitionDate] = useState("");
  const [busy, setBusy] = useState<
    "create" | "decode" | "review" | "retry" | null
  >(null);
  const [createdInventoryUnitId, setCreatedInventoryUnitId] = useState<
    string | null
  >(null);
  const [createdLinkedExistingOpenUnit, setCreatedLinkedExistingOpenUnit] =
    useState(false);
  const [createdStock, setCreatedStock] = useState<string | null>(null);
  const [decodeStatus, setDecodeStatus] = useState<DecodeStatus | null>(null);
  const [detailsConfirmed, setDetailsConfirmed] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [conditionKey, setConditionKey] = useState("");
  const [conditionDefinitions, setConditionDefinitions] = useState<
    readonly InventoryConditionDefinition[]
  >([]);
  const [locationId, setLocationId] = useState("");
  const [locations, setLocations] = useState<readonly IntakeLocation[]>([]);
  const [manualDuplicateDecision, setManualDuplicateDecision] = useState<
    "" | DuplicateDecision
  >("");
  const [manualDuplicateReason, setManualDuplicateReason] = useState("");
  const [manualFactsConfirmed, setManualFactsConfirmed] = useState(false);
  const [manualMode, setManualMode] = useState(false);
  const [manualReason, setManualReason] = useState("");
  const [modelYearHint, setModelYearHint] = useState("");
  const [notes, setNotes] = useState("");
  const [odometer, setOdometer] = useState("");
  const [price, setPrice] = useState("");
  const [reviewDecision, setReviewDecision] = useState<DuplicateDecision>(
    "reuse_existing_vehicle",
  );
  const [intakeApproved, setIntakeApproved] = useState(false);
  const [reviewReason, setReviewReason] = useState("");
  const [reviewed, setReviewed] = useState(false);
  const [retryReason, setRetryReason] = useState("");
  const [step, setStep] = useState<Step>(1);
  const [stockDefinitionId, setStockDefinitionId] = useState("");
  const [stockDefinitions, setStockDefinitions] = useState<
    readonly StockDefinition[]
  >([]);
  const [vehicleFields, setVehicleFields] = useState<VehicleFields>({
    bodyType: "",
    cylinders: "",
    drivetrain: "",
    engineLiters: "",
    fuelType: "",
    horsepower: "",
    make: "",
    model: "",
    modelYear: "",
    transmission: "",
    trimName: "",
  });
  const [vin, setVin] = useState("");
  const [workspaceId, setWorkspaceId] = useState("");
  const [workspaces, setWorkspaces] = useState<readonly WorkspaceOption[]>([]);

  const workspace = workspaces.find((item) => item.id === workspaceId);
  const manualRequiredDuplicateDecision = requiredDuplicateDecision(
    decodeStatus?.duplicateCandidates ?? [],
  );
  const linksExistingOpenUnit =
    (manualMode && manualDuplicateDecision === "override_open_duplicate") ||
    (!manualMode &&
      reviewed &&
      intakeApproved &&
      reviewDecision === "override_open_duplicate");
  const inventoryHref = previewEnabled
    ? "/inventory?preview=inventory"
    : "/inventory";

  function commandKey(scope: string, payload: unknown): string {
    const fingerprint = JSON.stringify(payload);
    const previous = idempotency.current.get(scope);
    if (previous?.fingerprint === fingerprint) return previous.key;
    const next = { fingerprint, key: crypto.randomUUID() } as const;
    idempotency.current.set(scope, next);
    return next.key;
  }

  const requestHeaders = useCallback(
    async (
      targetWorkspaceId: string,
      idempotencyKey?: string,
    ): Promise<Record<string, string>> => {
      const session = (await getBrowserSupabase().auth.getSession()).data
        .session;
      if (!session) {
        router.replace("/login");
        throw new TypeError("session_required");
      }
      return {
        Authorization: `Bearer ${session.access_token}`,
        ...(idempotencyKey
          ? {
              "Content-Type": "application/json",
              "Idempotency-Key": idempotencyKey,
            }
          : {}),
        "X-Correlation-Id": crypto.randomUUID(),
        "X-Request-Id": crypto.randomUUID(),
        "X-Workspace-Id": targetWorkspaceId,
      };
    },
    [router],
  );

  const loadIntakeConfiguration = useCallback(
    async (targetWorkspaceId: string) => {
      const sequence = ++intakeConfigurationRequestSequence.current;
      const isCurrentRequest = () =>
        activeWorkspaceId.current === targetWorkspaceId &&
        intakeConfigurationRequestSequence.current === sequence;
      if (!isCurrentRequest()) return;
      if (previewEnabled) {
        await Promise.resolve();
        if (isCurrentRequest()) {
          setStockDefinitions(previewStockDefinitions);
          setStockDefinitionId(previewStockDefinitions[0]!.id);
          setLocations(previewLocations);
          setLocationId(previewLocations[0]!.id);
          setConditionDefinitions(previewConditionDefinitions);
          setConditionKey(previewConditionDefinitions[0]!.key);
        }
        return;
      }
      const client = getBrowserSupabase();
      const [stockResult, locationResult, conditionResult] = await Promise.all([
        client
          .from("stock_number_definitions")
          .select("id,key,version,prefix,numeric_width")
          .eq("workspace_id", targetWorkspaceId)
          .eq("status", "active")
          .order("key")
          .order("version", { ascending: false }),
        client
          .from("locations")
          .select("id,name")
          .eq("workspace_id", targetWorkspaceId)
          .eq("status", "active")
          .order("name"),
        client
          .from("inventory_condition_definitions")
          .select("key,labels")
          .eq("workspace_id", targetWorkspaceId)
          .eq("status", "active")
          .order("key"),
      ]);
      const definitions = stockResult.error
        ? []
        : parseStockDefinitions(stockResult.data);
      const nextLocations = locationResult.error
        ? []
        : parseLocations(locationResult.data);
      const nextConditions = conditionResult.error
        ? []
        : parseConditionDefinitions(conditionResult.data);
      if (isCurrentRequest()) {
        setStockDefinitions(definitions);
        setStockDefinitionId(definitions[0]?.id ?? "");
        setLocations(nextLocations);
        setLocationId(nextLocations[0]?.id ?? "");
        setConditionDefinitions(nextConditions);
        setConditionKey(nextConditions[0]?.key ?? "");
      }
    },
    [previewEnabled],
  );

  useEffect(() => {
    let active = true;
    async function initialize() {
      let initializationWorkspaceId = "";
      try {
        if (previewEnabled) {
          setWorkspaces([previewWorkspace]);
          activeWorkspaceId.current = previewWorkspace.id;
          setWorkspaceId(previewWorkspace.id);
          await loadIntakeConfiguration(previewWorkspace.id);
          return;
        }
        const client = getBrowserSupabase();
        const session = (await client.auth.getSession()).data.session;
        if (!session) {
          router.replace("/login");
          return;
        }
        const result = await client
          .from("workspace_memberships")
          .select("id,workspaces!inner(id,name,default_currency,odometer_unit)")
          .eq("user_id", session.user.id)
          .eq("status", "active");
        if (result.error) throw result.error;
        const options = parseWorkspaceOptions(result.data);
        const first = options[0];
        if (!first) throw new TypeError("workspace_required");
        initializationWorkspaceId = first.id;
        if (active) {
          setWorkspaces(options);
          activeWorkspaceId.current = first.id;
          setWorkspaceId(first.id);
          await loadIntakeConfiguration(first.id);
        }
      } catch {
        if (
          active &&
          (!initializationWorkspaceId ||
            activeWorkspaceId.current === initializationWorkspaceId)
        ) {
          setErrorMessage(copy.errorDescription);
        }
      }
    }
    void initialize();
    return () => {
      active = false;
      flowGeneration.current += 1;
      pollAbortController.current?.abort();
    };
  }, [copy.errorDescription, loadIntakeConfiguration, previewEnabled, router]);

  const pollDecodeStatus = useCallback(async () => {
    if (!decodeStatus || pollInFlight.current) return;
    const context = decodeContext.current;
    if (
      !context ||
      context.workspaceId !== activeWorkspaceId.current ||
      context.requestId !== decodeStatus.vinDecodeRequestId
    )
      return;
    const sequence = ++pollRequestSequence.current;
    pollAbortController.current?.abort();
    const abortController = new AbortController();
    pollAbortController.current = abortController;
    const capturedFlowGeneration = flowGeneration.current;
    const isCurrentPoll = () =>
      activeWorkspaceId.current === context.workspaceId &&
      decodeContext.current?.workspaceId === context.workspaceId &&
      decodeContext.current?.requestId === context.requestId &&
      flowGeneration.current === capturedFlowGeneration &&
      pollRequestSequence.current === sequence &&
      !abortController.signal.aborted;
    pollInFlight.current = true;
    try {
      let next: DecodeStatus;
      if (previewEnabled) {
        previewPollCount.current += 1;
        await new Promise((resolve) => window.setTimeout(resolve, 80));
        if (previewPollCount.current === 1) {
          next = {
            ...decodeStatus,
            job: { ...decodeStatus.job, attemptCount: 1 },
            status: "running",
            statusLoaded: false,
          };
        } else if (
          [PREVIEW_DUPLICATE_FAILURE_VIN, PREVIEW_FAILURE_VIN].includes(
            decodeStatus.vin,
          ) &&
          previewRetryCount.current === 0
        ) {
          const terminalPreview = previewCompletedStatus(decodeStatus.vin);
          next = {
            ...decodeStatus,
            duplicateCandidates: terminalPreview.duplicateCandidates,
            job: {
              attemptCount: 1,
              maximumAttempts: 5,
              retryable: true,
              reviewRequired: terminalPreview.job.reviewRequired,
            },
            status: "dead_letter",
            statusLoaded: true,
          };
        } else {
          next = previewCompletedStatus(decodeStatus.vin);
        }
      } else {
        const response = await fetch(
          `/api/v1/vin/decode/${decodeStatus.vinDecodeRequestId}`,
          {
            cache: "no-store",
            headers: await requestHeaders(context.workspaceId),
            signal: abortController.signal,
          },
        );
        if (!response.ok) throw new TypeError("vin_status_failed");
        next = parseDecodeStatus(await response.json());
      }
      if (
        next.vinDecodeRequestId !== context.requestId ||
        next.vin !== decodeStatus.vin
      ) {
        throw new TypeError("vin_status_context_mismatch");
      }
      if (isCurrentPoll()) {
        if (
          next.statusLoaded &&
          ["dead_letter", "succeeded"].includes(next.status)
        ) {
          const mappingKey = `${next.vinDecodeRequestId}:${next.status}`;
          if (mappedRequestId.current !== mappingKey) {
            mappedRequestId.current = mappingKey;
            if (next.status === "succeeded") {
              const suggestions = next.suggestions;
              setVehicleFields({
                bodyType: suggestions?.bodyType ?? "",
                cylinders:
                  suggestions?.cylinders === null ||
                  suggestions?.cylinders === undefined
                    ? ""
                    : String(suggestions.cylinders),
                drivetrain: suggestions?.drivetrain ?? "",
                engineLiters: suggestions?.engineLiters ?? "",
                fuelType: suggestions?.fuelType ?? "",
                horsepower:
                  suggestions?.horsepower === null ||
                  suggestions?.horsepower === undefined
                    ? ""
                    : String(suggestions.horsepower),
                make: suggestions?.make ?? "",
                model: suggestions?.model ?? "",
                modelYear: suggestions?.modelYear
                  ? String(suggestions.modelYear)
                  : "",
                transmission: suggestions?.transmission ?? "",
                trimName: suggestions?.trimName ?? "",
              });
              setReviewed(next.duplicateReviewRecorded);
              setIntakeApproved(next.duplicateReviewApproved);
            }
            const nextDecision = requiredDuplicateDecision(
              next.duplicateCandidates,
            );
            if (nextDecision !== null) setReviewDecision(nextDecision);
            setManualDuplicateDecision(nextDecision ?? "");
            setManualDuplicateReason("");
          }
        }
        setDecodeStatus(next);
        setErrorMessage(null);
      }
    } catch {
      if (isCurrentPoll()) setErrorMessage(copy.errorDescription);
    } finally {
      if (pollRequestSequence.current === sequence) {
        pollInFlight.current = false;
      }
    }
  }, [copy.errorDescription, decodeStatus, previewEnabled, requestHeaders]);

  useEffect(() => {
    if (
      !decodeStatus ||
      (decodeStatus.statusLoaded &&
        !["queued", "retry_wait", "running"].includes(decodeStatus.status))
    ) {
      return;
    }
    const timer = window.setTimeout(
      () => void pollDecodeStatus(),
      previewEnabled ? 180 : 1_500,
    );
    return () => window.clearTimeout(timer);
  }, [decodeStatus, pollDecodeStatus, previewEnabled]);

  function resetFlow() {
    flowGeneration.current += 1;
    pollRequestSequence.current += 1;
    pollAbortController.current?.abort();
    pollInFlight.current = false;
    decodeContext.current = undefined;
    setBusy(null);
    mappedRequestId.current = null;
    previewPollCount.current = 0;
    previewRetryCount.current = 0;
    setCreatedInventoryUnitId(null);
    setCreatedLinkedExistingOpenUnit(false);
    setCreatedStock(null);
    setDecodeStatus(null);
    setDetailsConfirmed(false);
    setErrorMessage(null);
    setManualDuplicateDecision("");
    setManualDuplicateReason("");
    setManualFactsConfirmed(false);
    setManualMode(false);
    setManualReason("");
    setModelYearHint("");
    setAcquisitionDate("");
    setNotes("");
    setOdometer("");
    setPrice("");
    setReviewReason("");
    setReviewed(false);
    setIntakeApproved(false);
    setRetryReason("");
    setStep(1);
    setVehicleFields({
      bodyType: "",
      cylinders: "",
      drivetrain: "",
      engineLiters: "",
      fuelType: "",
      horsepower: "",
      make: "",
      model: "",
      modelYear: "",
      transmission: "",
      trimName: "",
    });
    setVin("");
  }

  async function chooseWorkspace(nextWorkspaceId: string) {
    if (!workspaces.some((workspace) => workspace.id === nextWorkspaceId))
      return;
    activeWorkspaceId.current = nextWorkspaceId;
    setWorkspaceId(nextWorkspaceId);
    resetFlow();
    setStockDefinitions([]);
    setStockDefinitionId("");
    setLocations([]);
    setLocationId("");
    setConditionDefinitions([]);
    setConditionKey("");
    try {
      await loadIntakeConfiguration(nextWorkspaceId);
    } catch {
      if (activeWorkspaceId.current === nextWorkspaceId) {
        setErrorMessage(copy.errorDescription);
      }
    }
  }

  async function startDecode(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalizedVin = vin.trim().toUpperCase();
    const year = modelYearHint.trim() ? Number(modelYearHint) : null;
    if (
      !workspaceId ||
      !VIN_PATTERN.test(normalizedVin) ||
      (year !== null && (!Number.isInteger(year) || year < 1886 || year > 2200))
    ) {
      setErrorMessage(copy.fieldRequired);
      return;
    }
    setBusy("decode");
    setErrorMessage(null);
    const targetWorkspaceId = workspaceId;
    const capturedFlowGeneration = ++flowGeneration.current;
    pollAbortController.current?.abort();
    decodeContext.current = undefined;
    const isCurrentFlow = () =>
      activeWorkspaceId.current === targetWorkspaceId &&
      flowGeneration.current === capturedFlowGeneration;
    try {
      const payload = { modelYear: year, vin: normalizedVin };
      let requestId: string;
      let jobStatus: JobStatus = "queued";
      let aggregateVersion = 1;
      if (previewEnabled) {
        await Promise.resolve();
        requestId = PREVIEW_REQUEST_ID;
      } else {
        const response = await fetch("/api/v1/vin/decode", {
          body: JSON.stringify(payload),
          headers: await requestHeaders(
            targetWorkspaceId,
            commandKey(`decode:${targetWorkspaceId}`, payload),
          ),
          method: "POST",
        });
        if (!response.ok) throw new TypeError("vin_decode_failed");
        const data = commandData(await response.json());
        if (
          typeof data.vinDecodeRequestId !== "string" ||
          typeof data.aggregateVersion !== "number" ||
          !Number.isSafeInteger(data.aggregateVersion) ||
          data.aggregateVersion < 1 ||
          !isJobStatus(data.jobStatus)
        ) {
          throw new TypeError("invalid_vin_decode_response");
        }
        requestId = data.vinDecodeRequestId;
        jobStatus = data.jobStatus;
        aggregateVersion = data.aggregateVersion;
      }
      if (!isCurrentFlow()) return;
      decodeContext.current = {
        requestId,
        workspaceId: targetWorkspaceId,
      };
      previewPollCount.current = 0;
      setVin(normalizedVin);
      setDecodeStatus(
        pendingDecodeStatus(
          normalizedVin,
          requestId,
          jobStatus,
          aggregateVersion,
        ),
      );
      setStep(2);
    } catch {
      if (isCurrentFlow()) setErrorMessage(copy.errorDescription);
    } finally {
      if (isCurrentFlow()) setBusy(null);
    }
  }

  async function retryDecode(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!decodeStatus || !retryReason.trim()) {
      setErrorMessage(copy.fieldRequired);
      return;
    }
    setBusy("retry");
    setErrorMessage(null);
    const context = decodeContext.current;
    const capturedFlowGeneration = flowGeneration.current;
    if (
      !context ||
      context.requestId !== decodeStatus.vinDecodeRequestId ||
      context.workspaceId !== activeWorkspaceId.current
    ) {
      setBusy(null);
      return;
    }
    const isCurrentFlow = () =>
      activeWorkspaceId.current === context.workspaceId &&
      decodeContext.current?.requestId === context.requestId &&
      flowGeneration.current === capturedFlowGeneration;
    try {
      const payload = { reason: retryReason.trim() };
      let nextStatus: JobStatus = "queued";
      if (previewEnabled) {
        previewRetryCount.current += 1;
        previewPollCount.current = 0;
        await Promise.resolve();
      } else {
        const response = await fetch(
          `/api/v1/vin/decode/${decodeStatus.vinDecodeRequestId}/retry`,
          {
            body: JSON.stringify(payload),
            headers: await requestHeaders(
              context.workspaceId,
              commandKey(
                `retry:${context.workspaceId}:${context.requestId}`,
                payload,
              ),
            ),
            method: "POST",
          },
        );
        if (!response.ok) throw new TypeError("vin_retry_failed");
        const data = commandData(await response.json());
        if (!isJobStatus(data.jobStatus)) {
          throw new TypeError("invalid_vin_retry_response");
        }
        nextStatus = data.jobStatus;
      }
      if (!isCurrentFlow()) return;
      setRetryReason("");
      setManualDuplicateDecision("");
      setManualDuplicateReason("");
      setManualFactsConfirmed(false);
      setManualMode(false);
      setManualReason("");
      setDecodeStatus({
        ...decodeStatus,
        job: { ...decodeStatus.job, retryable: false },
        status: nextStatus,
        statusLoaded: false,
      });
    } catch {
      if (isCurrentFlow()) setErrorMessage(copy.errorDescription);
    } finally {
      if (isCurrentFlow()) setBusy(null);
    }
  }

  async function reviewDuplicate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!decodeStatus || !reviewReason.trim()) {
      setErrorMessage(copy.fieldRequired);
      return;
    }
    setBusy("review");
    setErrorMessage(null);
    const context = decodeContext.current;
    const capturedFlowGeneration = flowGeneration.current;
    if (
      !context ||
      context.requestId !== decodeStatus.vinDecodeRequestId ||
      context.workspaceId !== activeWorkspaceId.current
    ) {
      setBusy(null);
      return;
    }
    const isCurrentFlow = () =>
      activeWorkspaceId.current === context.workspaceId &&
      decodeContext.current?.requestId === context.requestId &&
      flowGeneration.current === capturedFlowGeneration;
    try {
      const payload = {
        decision: reviewDecision,
        reason: reviewReason.trim(),
      };
      let approvedForIntake = true;
      let aggregateVersion = decodeStatus.aggregateVersion + 1;
      if (previewEnabled) {
        await Promise.resolve();
      } else {
        const response = await fetch(
          `/api/v1/vin/decode/${decodeStatus.vinDecodeRequestId}/duplicate-review`,
          {
            body: JSON.stringify(payload),
            headers: await requestHeaders(
              context.workspaceId,
              commandKey(
                `review:${context.workspaceId}:${context.requestId}`,
                payload,
              ),
            ),
            method: "POST",
          },
        );
        if (!response.ok) throw new TypeError("duplicate_review_failed");
        const data = commandData(await response.json());
        if (
          typeof data.approvedForIntake !== "boolean" ||
          typeof data.aggregateVersion !== "number" ||
          !Number.isSafeInteger(data.aggregateVersion) ||
          data.aggregateVersion < 1
        ) {
          throw new TypeError("invalid_duplicate_review_response");
        }
        approvedForIntake = data.approvedForIntake;
        aggregateVersion = data.aggregateVersion;
      }
      if (!isCurrentFlow()) return;
      setReviewed(true);
      setIntakeApproved(approvedForIntake);
      setDecodeStatus({
        ...decodeStatus,
        aggregateVersion,
        duplicateReviewApproved: approvedForIntake,
        duplicateReviewRecorded: true,
      });
      setReviewReason("");
      if (!approvedForIntake) {
        setErrorMessage(copy.openDuplicateBlocked);
      }
    } catch {
      if (isCurrentFlow()) setErrorMessage(copy.errorDescription);
    } finally {
      if (isCurrentFlow()) setBusy(null);
    }
  }

  function confirmVehicleDetails() {
    const duplicateCleared =
      !decodeStatus?.job.reviewRequired || (reviewed && intakeApproved);
    try {
      const vehicleFacts = confirmedVehicleFacts(vehicleFields);
      if (
        vehicleFacts.modelYear === null ||
        !vehicleFacts.make ||
        !vehicleFacts.model
      ) {
        throw new TypeError("required_vehicle_facts_missing");
      }
    } catch {
      setErrorMessage(copy.fieldRequired);
      return;
    }
    if (decodeStatus?.status !== "succeeded" || !duplicateCleared) {
      setErrorMessage(
        reviewed && !intakeApproved
          ? copy.openDuplicateBlocked
          : copy.fieldRequired,
      );
      return;
    }
    setManualMode(false);
    setDetailsConfirmed(true);
    setErrorMessage(null);
    setStep(3);
  }

  function confirmManualFacts(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    let vehicleFacts: ReturnType<typeof confirmedVehicleFacts>;
    try {
      vehicleFacts = confirmedVehicleFacts(vehicleFields);
    } catch {
      setErrorMessage(copy.fieldRequired);
      return;
    }
    if (
      decodeStatus?.status !== "dead_letter" ||
      !decodeStatus.statusLoaded ||
      !manualFactsConfirmed ||
      !manualReason.trim() ||
      !vehicleFacts.make ||
      !vehicleFacts.model ||
      vehicleFacts.modelYear === null ||
      (manualRequiredDuplicateDecision !== null &&
        manualDuplicateDecision !== manualRequiredDuplicateDecision) ||
      (manualDuplicateDecision !== "" && !manualDuplicateReason.trim())
    ) {
      setErrorMessage(copy.fieldRequired);
      return;
    }
    setManualMode(true);
    setDetailsConfirmed(true);
    setErrorMessage(null);
    setStep(3);
  }

  async function createInventory(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const isConfirmedFlow =
      !manualMode &&
      decodeStatus?.status === "succeeded" &&
      decodeStatus.vinDecodeResultId !== null;
    const isManualFlow =
      manualMode &&
      decodeStatus?.status === "dead_letter" &&
      decodeStatus.statusLoaded &&
      manualFactsConfirmed;
    if (
      !workspace ||
      !stockDefinitionId ||
      !locationId ||
      !conditionKey ||
      !decodeStatus ||
      (!isConfirmedFlow && !isManualFlow) ||
      !detailsConfirmed ||
      (isConfirmedFlow &&
        decodeStatus.job.reviewRequired &&
        (!reviewed || !intakeApproved))
    ) {
      setErrorMessage(copy.fieldRequired);
      return;
    }
    setBusy("create");
    setErrorMessage(null);
    const targetWorkspace = workspace;
    const context = decodeContext.current;
    const capturedFlowGeneration = flowGeneration.current;
    if (
      !context ||
      context.requestId !== decodeStatus.vinDecodeRequestId ||
      context.workspaceId !== targetWorkspace.id ||
      activeWorkspaceId.current !== targetWorkspace.id
    ) {
      setBusy(null);
      return;
    }
    const isCurrentFlow = () =>
      activeWorkspaceId.current === targetWorkspace.id &&
      decodeContext.current?.requestId === context.requestId &&
      flowGeneration.current === capturedFlowGeneration;
    try {
      const vehicleFacts = confirmedVehicleFacts(vehicleFields);
      const odometerValue =
        !linksExistingOpenUnit && odometer.trim() ? Number(odometer) : null;
      if (
        (isManualFlow &&
          (vehicleFacts.modelYear === null ||
            !vehicleFacts.make ||
            !vehicleFacts.model ||
            !manualReason.trim() ||
            (manualRequiredDuplicateDecision !== null &&
              manualDuplicateDecision !== manualRequiredDuplicateDecision) ||
            (manualDuplicateDecision !== "" &&
              !manualDuplicateReason.trim()))) ||
        (odometerValue !== null &&
          (!Number.isSafeInteger(odometerValue) || odometerValue < 0))
      ) {
        throw new TypeError("invalid_inventory_details");
      }
      const inventory = {
        acquisitionDate: linksExistingOpenUnit ? null : acquisitionDate || null,
        advertisedPriceMinor: linksExistingOpenUnit
          ? null
          : safeMoneyMinor(price, targetWorkspace.currencyCode),
        currencyCode: targetWorkspace.currencyCode,
        odometer:
          odometerValue === null
            ? null
            : { unit: targetWorkspace.odometerUnit, value: odometerValue },
        publicNotes: linksExistingOpenUnit ? null : notes.trim() || null,
      } as const;
      let endpoint: string;
      let idempotencyScope: string;
      let payload: unknown;
      if (isManualFlow) {
        endpoint = `/api/v1/vin/decode/${context.requestId}/manual-intake`;
        idempotencyScope = `manual-create:${targetWorkspace.id}:${context.requestId}`;
        payload = {
          conditionKey,
          confirmation: {
            accepted: true,
            expectedRequestVersion: decodeStatus.aggregateVersion,
          },
          duplicateDecision:
            manualDuplicateDecision === ""
              ? null
              : {
                  decision: manualDuplicateDecision,
                  reason: manualDuplicateReason.trim(),
                },
          inventory,
          locationId,
          manualReason: manualReason.trim(),
          stockDefinitionId,
          vehicleFacts,
        } as const;
      } else {
        if (decodeStatus.vinDecodeResultId === null) {
          throw new TypeError("vin_decode_result_required");
        }
        endpoint = "/api/v1/inventory-units";
        idempotencyScope = `create:${targetWorkspace.id}:${context.requestId}`;
        payload = {
          conditionKey,
          confirmation: {
            accepted: true,
            expectedRequestVersion: decodeStatus.aggregateVersion,
            vinDecodeResultId: decodeStatus.vinDecodeResultId,
          },
          inventory,
          locationId,
          stockDefinitionId,
          vehicleFacts,
          vinDecodeRequestId: decodeStatus.vinDecodeRequestId,
        } as const;
      }
      let inventoryUnitId: string;
      let linkedExistingOpenUnit: boolean;
      let stockNumber: string;
      if (previewEnabled) {
        await Promise.resolve();
        const openCandidate = decodeStatus.duplicateCandidates.find(
          (candidate) => candidate.kind === "open_inventory",
        );
        inventoryUnitId = linksExistingOpenUnit
          ? (openCandidate?.inventoryUnitId ?? PREVIEW_INVENTORY_UNIT_ID)
          : PREVIEW_INVENTORY_UNIT_ID;
        stockNumber = linksExistingOpenUnit
          ? (openCandidate?.stockNumber ?? "SYN-00120")
          : isManualFlow
            ? "SYN-M0091"
            : "SYN-00991";
        linkedExistingOpenUnit = linksExistingOpenUnit;
      } else {
        const response = await fetch(endpoint, {
          body: JSON.stringify(payload),
          headers: await requestHeaders(
            targetWorkspace.id,
            commandKey(idempotencyScope, payload),
          ),
          method: "POST",
        });
        if (!response.ok) throw new TypeError("inventory_create_failed");
        const data = commandData(await response.json());
        if (
          typeof data.inventoryUnitId !== "string" ||
          typeof data.linkedExistingOpenUnit !== "boolean" ||
          typeof data.stockNumber !== "string"
        ) {
          throw new TypeError("invalid_inventory_create_response");
        }
        inventoryUnitId = data.inventoryUnitId;
        linkedExistingOpenUnit = data.linkedExistingOpenUnit;
        stockNumber = data.stockNumber;
      }
      if (!isCurrentFlow()) return;
      setCreatedInventoryUnitId(inventoryUnitId);
      setCreatedLinkedExistingOpenUnit(linkedExistingOpenUnit);
      setCreatedStock(stockNumber);
    } catch {
      if (isCurrentFlow()) setErrorMessage(copy.errorDescription);
    } finally {
      if (isCurrentFlow()) setBusy(null);
    }
  }

  const progress = createdStock ? 3 : step;
  const stepLabels = [copy.stepVin, copy.stepDecode, copy.stepDetails] as const;
  const duplicateCleared =
    !decodeStatus?.job.reviewRequired || (reviewed && intakeApproved);
  const shellWorkspaces =
    workspaces.length === 0
      ? [{ id: "", name: copy.workspaceLoading }]
      : busy !== null
        ? workspaces.filter((workspace) => workspace.id === workspaceId)
        : workspaces;

  return (
    <OperatorShell
      attentionCount={errorMessage || busy !== null ? 1 : 0}
      contextLabel={previewEnabled ? copy.developmentPreview : copy.backAction}
      copy={{
        appName: "Vynlo",
        attention: copy.pendingStatus,
        environment: copy.heading,
        localeLabel: copy.localeLabel,
        localeNames: copy.localeNames,
        navigationLabel: `${copy.navigationLabel} · Vynlo`,
        skipToContent: copy.skipToContent,
        workspaceLabel: copy.workspaceLabel,
      }}
      current="inventory"
      locale={locale}
      mainId="inventory-intake-main"
      onWorkspaceChange={(nextWorkspaceId) => {
        if (busy === null) void chooseWorkspace(nextWorkspaceId);
      }}
      previewMode={previewEnabled ? "inventory" : null}
      selectedWorkspaceId={workspaceId}
      summary={copy.introduction}
      title={copy.heading}
      workspaces={shellWorkspaces}
    >
      <div className="inventory-intake__main">
        <a className="back-link" href={inventoryHref}>
          <ArrowLeft aria-hidden="true" size={17} />
          {copy.backAction}
        </a>

        <nav
          aria-label={copy.navigationLabel}
          className="inventory-intake__progress"
        >
          <p>{interpolate(copy.progressLabel, { current: progress })}</p>
          <ol>
            {stepLabels.map((label, index) => {
              const number = (index + 1) as Step;
              const complete = createdStock !== null || number < step;
              return (
                <li
                  aria-current={
                    !createdStock && number === step ? "step" : undefined
                  }
                  data-complete={complete}
                  key={label}
                >
                  <span aria-hidden="true">
                    {complete ? <Check size={15} /> : number}
                  </span>
                  <strong>{label}</strong>
                </li>
              );
            })}
          </ol>
        </nav>

        {errorMessage ? (
          <div className="inventory-intake__error" role="alert">
            <CircleAlert aria-hidden="true" size={20} />
            <div>
              <strong>{copy.errorHeading}</strong>
              <p>{errorMessage}</p>
            </div>
          </div>
        ) : null}

        {step === 1 && !createdStock ? (
          <section
            aria-labelledby="vin-step-heading"
            className="inventory-intake__step"
          >
            <header>
              <span>01</span>
              <div>
                <h2 id="vin-step-heading">{copy.stepVin}</h2>
                <p>{copy.vinHint}</p>
              </div>
            </header>
            <form onSubmit={startDecode}>
              <label>
                <span>{copy.vinLabel}</span>
                <Input
                  autoCapitalize="characters"
                  autoComplete="off"
                  maxLength={17}
                  minLength={17}
                  onChange={(event) => setVin(event.target.value.toUpperCase())}
                  required
                  value={vin}
                />
              </label>
              <label>
                <span>{copy.modelYearHintLabel}</span>
                <Input
                  inputMode="numeric"
                  max="2200"
                  min="1886"
                  onChange={(event) => setModelYearHint(event.target.value)}
                  type="number"
                  value={modelYearHint}
                />
              </label>
              <Button disabled={busy !== null || !workspaceId} type="submit">
                {busy === "decode" ? (
                  <LoaderCircle
                    aria-hidden="true"
                    className="inventory-intake__spinner"
                    size={17}
                  />
                ) : null}
                {busy === "decode"
                  ? copy.startingDecode
                  : copy.startDecodeAction}
              </Button>
            </form>
          </section>
        ) : null}

        {step === 2 && decodeStatus && !createdStock ? (
          <section
            aria-labelledby="decode-step-heading"
            className="inventory-intake__step"
          >
            <header>
              <span>02</span>
              <div>
                <h2 id="decode-step-heading">{copy.decodeHeading}</h2>
                <p>{copy.decodeDescription}</p>
              </div>
            </header>

            <div
              aria-live="polite"
              className="inventory-intake__job"
              role="status"
            >
              {["queued", "retry_wait", "running"].includes(
                decodeStatus.status,
              ) ? (
                <LoaderCircle
                  aria-hidden="true"
                  className="inventory-intake__spinner"
                  size={22}
                />
              ) : decodeStatus.status === "succeeded" ? (
                <Check aria-hidden="true" size={22} />
              ) : (
                <CircleAlert aria-hidden="true" size={22} />
              )}
              <div>
                <strong>{statusLabel(copy, decodeStatus.status)}</strong>
                <p>
                  {interpolate(copy.jobAttempt, {
                    attempt: decodeStatus.job.attemptCount,
                    maximum: decodeStatus.job.maximumAttempts,
                  })}
                </p>
              </div>
            </div>

            {decodeStatus.job.retryable &&
            ["cancelled", "dead_letter"].includes(decodeStatus.status) ? (
              <form className="inventory-intake__retry" onSubmit={retryDecode}>
                <div>
                  <h3>{copy.retryHeading}</h3>
                  <p>{copy.retryDescription}</p>
                </div>
                <label>
                  <span>{copy.retryReasonLabel}</span>
                  <Textarea
                    maxLength={2_000}
                    onChange={(event) => setRetryReason(event.target.value)}
                    required
                    value={retryReason}
                  />
                </label>
                <Button
                  disabled={busy !== null || !retryReason.trim()}
                  type="submit"
                  variant="outline"
                >
                  {busy === "retry" ? (
                    <LoaderCircle
                      aria-hidden="true"
                      className="inventory-intake__spinner"
                      size={17}
                    />
                  ) : (
                    <RotateCcw aria-hidden="true" size={17} />
                  )}
                  {copy.retryAction}
                </Button>
              </form>
            ) : null}

            {decodeStatus.status === "dead_letter" &&
            decodeStatus.statusLoaded ? (
              <form
                aria-labelledby="manual-intake-heading"
                className="inventory-intake__manual"
                onSubmit={confirmManualFacts}
              >
                <header>
                  <h3 id="manual-intake-heading">{copy.manualHeading}</h3>
                  <p>{copy.manualDescription}</p>
                </header>
                <VehicleFactFields
                  copy={copy}
                  fields={vehicleFields}
                  onFieldChange={(field, value) =>
                    setVehicleFields((current) => ({
                      ...current,
                      [field]: value,
                    }))
                  }
                />
                <label>
                  <span>{copy.manualReasonLabel}</span>
                  <Textarea
                    maxLength={2_000}
                    onChange={(event) => setManualReason(event.target.value)}
                    required
                    value={manualReason}
                  />
                </label>
                {decodeStatus.duplicateCandidates.length > 0 ? (
                  <section
                    aria-labelledby="manual-duplicate-candidates-heading"
                    className="inventory-intake__duplicates"
                  >
                    <header>
                      <h4 id="manual-duplicate-candidates-heading">
                        {copy.duplicateHeading}
                      </h4>
                      <p>{copy.duplicateDescription}</p>
                    </header>
                    <ul>
                      {decodeStatus.duplicateCandidates.map((candidate) => (
                        <li key={candidate.id}>
                          <strong>
                            {candidateKindLabel(copy, candidate.kind)}
                          </strong>
                          <span>
                            {candidate.stockNumber
                              ? `${copy.stockLabel} ${candidate.stockNumber}`
                              : copy.candidateVehicle}
                            {candidate.inventoryStatus
                              ? ` · ${inventoryStatusLabel(
                                  copy,
                                  candidate.inventoryStatus,
                                )}`
                              : ""}
                          </span>
                        </li>
                      ))}
                    </ul>
                  </section>
                ) : null}
                <fieldset className="inventory-intake__manual-relationship">
                  <legend>{copy.manualDuplicateLegend}</legend>
                  <label>
                    <span>{copy.manualDuplicateDecisionLabel}</span>
                    <NativeSelect
                      onChange={(event) =>
                        setManualDuplicateDecision(
                          event.target.value as "" | DuplicateDecision,
                        )
                      }
                      value={manualDuplicateDecision}
                    >
                      {manualRequiredDuplicateDecision === null ? (
                        <option value="">{copy.manualDuplicateNone}</option>
                      ) : (
                        <option value={manualRequiredDuplicateDecision}>
                          {decisionLabel(copy, manualRequiredDuplicateDecision)}
                        </option>
                      )}
                    </NativeSelect>
                  </label>
                  {manualDuplicateDecision !== "" ? (
                    <label>
                      <span>{copy.manualDuplicateReasonLabel}</span>
                      <Textarea
                        maxLength={2_000}
                        onChange={(event) =>
                          setManualDuplicateReason(event.target.value)
                        }
                        required
                        value={manualDuplicateReason}
                      />
                    </label>
                  ) : null}
                </fieldset>
                <label className="inventory-intake__fact-confirmation">
                  <Checkbox
                    checked={manualFactsConfirmed}
                    onCheckedChange={(checked) =>
                      setManualFactsConfirmed(checked === true)
                    }
                  />
                  <span>{copy.manualConfirmationLabel}</span>
                </label>
                <Button
                  disabled={
                    busy !== null ||
                    !manualFactsConfirmed ||
                    !manualReason.trim() ||
                    !vehicleFields.modelYear.trim() ||
                    !vehicleFields.make.trim() ||
                    !vehicleFields.model.trim() ||
                    (manualRequiredDuplicateDecision !== null &&
                      manualDuplicateDecision !==
                        manualRequiredDuplicateDecision) ||
                    (manualDuplicateDecision !== "" &&
                      !manualDuplicateReason.trim())
                  }
                  type="submit"
                >
                  {copy.manualContinueAction}
                </Button>
              </form>
            ) : null}

            {decodeStatus.status === "succeeded" ? (
              <div className="inventory-intake__confirmation">
                <section aria-labelledby="suggestions-heading">
                  <header>
                    <h3 id="suggestions-heading">{copy.suggestionsHeading}</h3>
                    <p>{copy.suggestionsDescription}</p>
                  </header>
                  <VehicleFactFields
                    copy={copy}
                    fields={vehicleFields}
                    onFieldChange={(field, value) =>
                      setVehicleFields((current) => ({
                        ...current,
                        [field]: value,
                      }))
                    }
                  />
                  {decodeStatus.warnings.length > 0 ? (
                    <div className="inventory-intake__warnings">
                      <h4>{copy.warningsHeading}</h4>
                      <ul>
                        {decodeStatus.warnings.map((warning) => (
                          <li key={warning}>{warning}</li>
                        ))}
                      </ul>
                    </div>
                  ) : null}
                </section>

                {decodeStatus.job.reviewRequired ? (
                  <section
                    aria-labelledby="duplicate-review-heading"
                    className="inventory-intake__duplicates"
                  >
                    <header>
                      <h3 id="duplicate-review-heading">
                        {copy.duplicateHeading}
                      </h3>
                      <p>{copy.duplicateDescription}</p>
                    </header>
                    <ul>
                      {decodeStatus.duplicateCandidates.map((candidate) => (
                        <li key={candidate.id}>
                          <strong>
                            {candidateKindLabel(copy, candidate.kind)}
                          </strong>
                          <span>
                            {candidate.stockNumber
                              ? `${copy.stockLabel} ${candidate.stockNumber}`
                              : copy.candidateVehicle}
                            {candidate.inventoryStatus
                              ? ` · ${inventoryStatusLabel(
                                  copy,
                                  candidate.inventoryStatus,
                                )}`
                              : ""}
                          </span>
                        </li>
                      ))}
                    </ul>
                    {reviewed ? (
                      <p className="inventory-intake__reviewed" role="status">
                        {intakeApproved ? (
                          <Check aria-hidden="true" size={17} />
                        ) : (
                          <CircleAlert aria-hidden="true" size={17} />
                        )}
                        {intakeApproved
                          ? reviewDecision === "override_open_duplicate"
                            ? copy.openDuplicateReviewedStatus
                            : copy.reviewedStatus
                          : copy.openDuplicateBlocked}
                      </p>
                    ) : (
                      <form onSubmit={reviewDuplicate}>
                        <label>
                          <span>{copy.decisionLabel}</span>
                          <NativeSelect
                            onChange={(event) =>
                              setReviewDecision(
                                event.target.value as DuplicateDecision,
                              )
                            }
                            value={reviewDecision}
                          >
                            <option value={reviewDecision}>
                              {decisionLabel(copy, reviewDecision)}
                            </option>
                          </NativeSelect>
                        </label>
                        <label>
                          <span>{copy.reviewReasonLabel}</span>
                          <Textarea
                            maxLength={2_000}
                            onChange={(event) =>
                              setReviewReason(event.target.value)
                            }
                            required
                            value={reviewReason}
                          />
                        </label>
                        <Button
                          disabled={busy !== null || !reviewReason.trim()}
                          type="submit"
                          variant="outline"
                        >
                          {busy === "review" ? (
                            <LoaderCircle
                              aria-hidden="true"
                              className="inventory-intake__spinner"
                              size={17}
                            />
                          ) : null}
                          {busy === "review"
                            ? copy.reviewing
                            : copy.reviewAction}
                        </Button>
                      </form>
                    )}
                  </section>
                ) : null}

                <Button
                  disabled={!duplicateCleared || busy !== null}
                  onClick={confirmVehicleDetails}
                  type="button"
                >
                  {copy.confirmDetailsAction}
                </Button>
              </div>
            ) : null}
          </section>
        ) : null}

        {step === 3 && !createdStock ? (
          <section
            aria-labelledby="details-step-heading"
            className="inventory-intake__step"
          >
            <header>
              <span>03</span>
              <div>
                <h2 id="details-step-heading">{copy.vehicleDetailsHeading}</h2>
                <p>
                  {linksExistingOpenUnit
                    ? copy.linkInventoryDescription
                    : manualMode
                      ? copy.manualInventoryDescription
                      : copy.vehicleDetailsDescription}
                </p>
              </div>
            </header>
            {stockDefinitions.length === 0 ? (
              <div className="inventory-intake__stock-warning" role="alert">
                <CircleAlert aria-hidden="true" size={20} />
                {copy.noStockDefinition}
              </div>
            ) : null}
            {locations.length === 0 ? (
              <div className="inventory-intake__stock-warning" role="alert">
                <CircleAlert aria-hidden="true" size={20} />
                {copy.noActiveLocation}
              </div>
            ) : null}
            {conditionDefinitions.length === 0 ? (
              <div className="inventory-intake__stock-warning" role="alert">
                <CircleAlert aria-hidden="true" size={20} />
                {copy.noConditionDefinition}
              </div>
            ) : null}
            <form onSubmit={createInventory}>
              <div className="inventory-intake__field-pair">
                <label>
                  <span>{copy.locationLabel}</span>
                  <NativeSelect
                    onChange={(event) => setLocationId(event.target.value)}
                    required
                    value={locationId}
                  >
                    {locations.map((location) => (
                      <option key={location.id} value={location.id}>
                        {location.name}
                      </option>
                    ))}
                  </NativeSelect>
                </label>
                <label>
                  <span>{copy.conditionLabel}</span>
                  <NativeSelect
                    onChange={(event) => setConditionKey(event.target.value)}
                    required
                    value={conditionKey}
                  >
                    {conditionDefinitions.map((definition) => (
                      <option key={definition.key} value={definition.key}>
                        {conditionDefinitionLabel(definition, locale)}
                      </option>
                    ))}
                  </NativeSelect>
                </label>
              </div>
              <label>
                <span>{copy.stockDefinitionLabel}</span>
                <NativeSelect
                  onChange={(event) => setStockDefinitionId(event.target.value)}
                  required
                  value={stockDefinitionId}
                >
                  {stockDefinitions.map((definition) => (
                    <option key={definition.id} value={definition.id}>
                      {definition.key} · {definition.prefix}
                      {"0".repeat(Math.min(definition.numericWidth, 8))} · v
                      {definition.version}
                    </option>
                  ))}
                </NativeSelect>
              </label>
              {!linksExistingOpenUnit ? (
                <>
                  <div className="inventory-intake__field-pair">
                    <label>
                      <span>{copy.acquisitionDateLabel}</span>
                      <Input
                        onChange={(event) =>
                          setAcquisitionDate(event.target.value)
                        }
                        type="date"
                        value={acquisitionDate}
                      />
                    </label>
                    <label>
                      <span>
                        {copy.odometerLabel} · {workspace?.odometerUnit ?? ""}
                      </span>
                      <Input
                        inputMode="numeric"
                        min="0"
                        onChange={(event) => setOdometer(event.target.value)}
                        type="number"
                        value={odometer}
                      />
                    </label>
                  </div>
                  <div className="inventory-intake__field-pair">
                    <label>
                      <span>{copy.priceLabel}</span>
                      <Input
                        inputMode="decimal"
                        onChange={(event) => setPrice(event.target.value)}
                        placeholder="0.00"
                        value={price}
                      />
                    </label>
                    <label>
                      <span>{copy.currencyLabel}</span>
                      <Input
                        disabled
                        readOnly
                        value={workspace?.currencyCode ?? ""}
                      />
                    </label>
                  </div>
                  <label>
                    <span>{copy.notesLabel}</span>
                    <Textarea
                      maxLength={4_000}
                      onChange={(event) => setNotes(event.target.value)}
                      value={notes}
                    />
                  </label>
                </>
              ) : null}
              <Button
                disabled={
                  busy !== null ||
                  !stockDefinitionId ||
                  !locationId ||
                  !conditionKey ||
                  (!manualMode &&
                    decodeStatus?.job.reviewRequired === true &&
                    (!reviewed || !intakeApproved))
                }
                type="submit"
              >
                {busy === "create" ? (
                  <LoaderCircle
                    aria-hidden="true"
                    className="inventory-intake__spinner"
                    size={17}
                  />
                ) : null}
                {busy === "create"
                  ? linksExistingOpenUnit
                    ? copy.linkingOpenInventory
                    : copy.creating
                  : linksExistingOpenUnit
                    ? copy.linkOpenInventoryAction
                    : manualMode
                      ? copy.manualCreateAction
                      : copy.createAction}
              </Button>
            </form>
          </section>
        ) : null}

        {createdStock && createdInventoryUnitId ? (
          <div className="inventory-intake__completion">
            <section className="inventory-intake__success" role="status">
              <span aria-hidden="true">
                <Check size={26} />
              </span>
              <div>
                <h2>
                  {createdLinkedExistingOpenUnit
                    ? copy.linkedHeading
                    : copy.createdHeading}
                </h2>
                <p>
                  {interpolate(
                    createdLinkedExistingOpenUnit
                      ? copy.linkedDescription
                      : copy.createdDescription,
                    { stock: createdStock },
                  )}
                </p>
                <Button asChild>
                  <a href={inventoryHref}>{copy.viewInventoryAction}</a>
                </Button>
              </div>
            </section>
            <VehiclePhotoUpload
              copy={copy}
              inventoryUnitId={createdInventoryUnitId}
              locale={locale}
              previewEnabled={previewEnabled}
              workspaceId={workspaceId}
            />
          </div>
        ) : null}
      </div>
    </OperatorShell>
  );
}
