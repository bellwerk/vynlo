"use client";

import { Button } from "@vynlo/ui-web/components/button";
import {
  Bookmark,
  CircleAlert,
  Eye,
  Images,
  LoaderCircle,
  Plus,
  RotateCcw,
  Search,
  Trash2,
} from "lucide-react";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import type { InventoryCopy } from "../i18n/inventory-messages";
import type { Locale } from "../i18n/messages";
import {
  formatMinorMoney,
  minorMoneyToMajorInput,
  parseMajorMoneyToMinor,
} from "../lib/inventory-money";
import { getBrowserSupabase } from "../lib/supabase-browser";
import { LocaleSwitcher } from "./locale-switcher";

type CanonicalStatus = "active" | "archived" | "closed" | "draft" | "pending";
type LoadPhase = "empty" | "error" | "loading" | "ready";

interface InventoryItem {
  readonly advertisedPriceMinor: string | null;
  readonly canonicalStatus: CanonicalStatus;
  readonly currencyCode: string;
  readonly daysInStock: number;
  readonly inventoryUnitId: string;
  readonly locationId: string | null;
  readonly locationName: string | null;
  readonly make: string | null;
  readonly model: string | null;
  readonly modelYear: number | null;
  readonly stockNumber: string;
  readonly trim: string | null;
  readonly updatedAt: string;
  readonly vin: string;
}

interface WorkspaceOption {
  readonly currencyCode: string;
  readonly id: string;
  readonly name: string;
}

interface LocationOption {
  readonly id: string;
  readonly name: string;
}

interface SavedInventoryView {
  readonly density: "comfortable" | "compact";
  readonly filters: Readonly<Record<string, unknown>>;
  readonly isOwner: boolean;
  readonly layout: "responsive" | "cards" | "table";
  readonly name: string;
  readonly savedViewId: string;
  readonly shareScope: "private" | "workspace";
  readonly sort: Readonly<{ direction: "asc" | "desc"; key: string }>;
  readonly version: number;
  readonly visibleColumns: readonly string[];
}

interface FilterValues {
  readonly locationId: string;
  readonly maximumAge: string;
  readonly maximumPrice: string;
  readonly minimumAge: string;
  readonly minimumPrice: string;
  readonly query: string;
  readonly status: "" | CanonicalStatus;
}

interface NormalizedFilters {
  readonly locationId: string | null;
  readonly maximumAge: number | null;
  readonly maximumPriceMinor: string | null;
  readonly minimumAge: number | null;
  readonly minimumPriceMinor: string | null;
  readonly query: string | null;
  readonly status: CanonicalStatus | null;
}

const emptyFilters: FilterValues = Object.freeze({
  locationId: "",
  maximumAge: "",
  maximumPrice: "",
  minimumAge: "",
  minimumPrice: "",
  query: "",
  status: "",
});

const previewWorkspace: WorkspaceOption = Object.freeze({
  currencyCode: "CAD",
  id: "00000000-0000-4000-8000-000000000201",
  name: "Sample workspace",
});

const previewLocations: readonly LocationOption[] = Object.freeze([
  { id: "00000000-0000-4000-8000-000000000221", name: "Main showroom" },
  { id: "00000000-0000-4000-8000-000000000222", name: "North lot" },
  { id: "00000000-0000-4000-8000-000000000223", name: "Service intake" },
]);

const previewItems: readonly InventoryItem[] = Object.freeze([
  {
    advertisedPriceMinor: "5499500",
    canonicalStatus: "active",
    currencyCode: "CAD",
    daysInStock: 12,
    inventoryUnitId: "00000000-0000-4000-8000-000000000211",
    locationId: previewLocations[0]!.id,
    locationName: "Main showroom",
    make: "Volvo",
    model: "XC60",
    modelYear: 2024,
    stockNumber: "SYN-24018",
    trim: "Plus",
    updatedAt: "2026-07-16T14:00:00.000Z",
    vin: "1TEST23ABCD456789",
  },
  {
    advertisedPriceMinor: "3875000",
    canonicalStatus: "pending",
    currencyCode: "CAD",
    daysInStock: 37,
    inventoryUnitId: "00000000-0000-4000-8000-000000000212",
    locationId: previewLocations[1]!.id,
    locationName: "North lot",
    make: "Toyota",
    model: "RAV4",
    modelYear: 2023,
    stockNumber: "SYN-23042",
    trim: "XLE",
    updatedAt: "2026-07-15T18:30:00.000Z",
    vin: "2SAMP34EFGH567890",
  },
  {
    advertisedPriceMinor: null,
    canonicalStatus: "draft",
    currencyCode: "CAD",
    daysInStock: 3,
    inventoryUnitId: "00000000-0000-4000-8000-000000000213",
    locationId: previewLocations[2]!.id,
    locationName: "Service intake",
    make: "Ford",
    model: "Transit",
    modelYear: 2022,
    stockNumber: "SYN-22007",
    trim: null,
    updatedAt: "2026-07-16T12:10:00.000Z",
    vin: "3DEMA45JKLM678901",
  },
]);

const previewSavedViews: readonly SavedInventoryView[] = Object.freeze([
  {
    density: "comfortable",
    filters: { locationIds: [previewLocations[0]!.id], status: ["active"] },
    isOwner: true,
    layout: "responsive",
    name: "Showroom inventory",
    savedViewId: "00000000-0000-4000-8000-000000000231",
    shareScope: "private",
    sort: { direction: "desc", key: "updated_at" },
    version: 1,
    visibleColumns: ["stock", "vehicle", "location", "state"],
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

function parseInventoryItem(value: unknown): InventoryItem | null {
  const item = record(value);
  if (!item) {
    return null;
  }
  const status = item.canonicalStatus;
  const statuses: readonly CanonicalStatus[] = [
    "active",
    "archived",
    "closed",
    "draft",
    "pending",
  ];
  const price = nullableString(item.advertisedPriceMinor);
  const location = nullableString(item.locationName);
  const locationId = nullableString(item.locationId);
  const make = nullableString(item.make);
  const model = nullableString(item.model);
  const trim = nullableString(item.trim);
  const modelYear = item.modelYear;

  if (
    typeof item.inventoryUnitId !== "string" ||
    typeof item.stockNumber !== "string" ||
    typeof item.currencyCode !== "string" ||
    !/^[A-Z]{3}$/u.test(item.currencyCode) ||
    typeof item.daysInStock !== "number" ||
    !Number.isInteger(item.daysInStock) ||
    item.daysInStock < 0 ||
    typeof item.vin !== "string" ||
    !/^[A-HJ-NPR-Z0-9]{17}$/u.test(item.vin) ||
    typeof item.updatedAt !== "string" ||
    !statuses.includes(status as CanonicalStatus) ||
    price === undefined ||
    (price !== null && !/^(?:0|[1-9]\d{0,18})$/u.test(price)) ||
    location === undefined ||
    locationId === undefined ||
    make === undefined ||
    model === undefined ||
    trim === undefined ||
    (modelYear !== null &&
      (typeof modelYear !== "number" || !Number.isInteger(modelYear)))
  ) {
    return null;
  }

  return {
    advertisedPriceMinor: price,
    canonicalStatus: status as CanonicalStatus,
    currencyCode: item.currencyCode,
    daysInStock: item.daysInStock,
    inventoryUnitId: item.inventoryUnitId,
    locationId,
    locationName: location,
    make,
    model,
    modelYear: modelYear as number | null,
    stockNumber: item.stockNumber,
    trim,
    updatedAt: item.updatedAt,
    vin: item.vin,
  };
}

function parseLocationEnvelope(value: unknown): readonly LocationOption[] {
  const envelope = record(value);
  const data = record(envelope?.data);
  if (!Array.isArray(data?.items))
    throw new TypeError("invalid_locations_response");
  return data.items.map((value) => {
    const item = record(value);
    if (typeof item?.id !== "string" || typeof item.name !== "string") {
      throw new TypeError("invalid_locations_response");
    }
    return { id: item.id, name: item.name };
  });
}

function parseSavedViewsEnvelope(
  value: unknown,
): readonly SavedInventoryView[] {
  const envelope = record(value);
  const data = record(envelope?.data);
  if (!Array.isArray(data?.items))
    throw new TypeError("invalid_saved_views_response");
  return data.items.map((value) => {
    const item = record(value);
    const filters = record(item?.filters);
    const sort = record(item?.sort);
    if (
      typeof item?.savedViewId !== "string" ||
      typeof item.name !== "string" ||
      typeof item.version !== "number" ||
      typeof item.isOwner !== "boolean" ||
      !["comfortable", "compact"].includes(String(item.density)) ||
      !["responsive", "cards", "table"].includes(String(item.layout)) ||
      !["private", "workspace"].includes(String(item.shareScope)) ||
      !filters ||
      !sort ||
      !["asc", "desc"].includes(String(sort.direction)) ||
      typeof sort.key !== "string" ||
      !Array.isArray(item.visibleColumns) ||
      item.visibleColumns.some((column) => typeof column !== "string")
    ) {
      throw new TypeError("invalid_saved_views_response");
    }
    return {
      density: item.density as SavedInventoryView["density"],
      filters,
      isOwner: item.isOwner,
      layout: item.layout as SavedInventoryView["layout"],
      name: item.name,
      savedViewId: item.savedViewId,
      shareScope: item.shareScope as SavedInventoryView["shareScope"],
      sort: {
        direction: sort.direction as "asc" | "desc",
        key: sort.key,
      },
      version: item.version,
      visibleColumns: item.visibleColumns as string[],
    };
  });
}

function parseInventoryEnvelope(value: unknown): readonly InventoryItem[] {
  const envelope = record(value);
  const data = record(envelope?.data);
  if (!Array.isArray(data?.items)) {
    throw new TypeError("invalid_inventory_response");
  }
  const items = data.items.map(parseInventoryItem);
  if (items.some((item) => item === null)) {
    throw new TypeError("invalid_inventory_response");
  }
  return items as readonly InventoryItem[];
}

function parseWorkspaceOptions(value: unknown): readonly WorkspaceOption[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.flatMap((membership) => {
    const source = record(membership);
    const relation = source?.workspaces;
    const workspace = Array.isArray(relation)
      ? record(relation[0])
      : record(relation);
    return typeof workspace?.id === "string" &&
      typeof workspace.name === "string" &&
      typeof workspace.default_currency === "string" &&
      /^[A-Z]{3}$/u.test(workspace.default_currency)
      ? [
          {
            currencyCode: workspace.default_currency,
            id: workspace.id,
            name: workspace.name,
          },
        ]
      : [];
  });
}

function parseAge(value: string): number | null {
  const normalized = value.trim();
  if (normalized === "") {
    return null;
  }
  if (!/^\d{1,5}$/u.test(normalized)) {
    throw new TypeError("invalid_age_range");
  }
  return Number(normalized);
}

function normalizeFilters(
  filters: FilterValues,
  currencyCode: string,
): NormalizedFilters {
  const normalized = {
    locationId: filters.locationId || null,
    maximumAge: parseAge(filters.maximumAge),
    maximumPriceMinor: parseMajorMoneyToMinor(
      filters.maximumPrice,
      currencyCode,
    ),
    minimumAge: parseAge(filters.minimumAge),
    minimumPriceMinor: parseMajorMoneyToMinor(
      filters.minimumPrice,
      currencyCode,
    ),
    query: filters.query.trim() || null,
    status: filters.status || null,
  } as const;

  if (
    (normalized.minimumAge !== null &&
      normalized.maximumAge !== null &&
      normalized.minimumAge > normalized.maximumAge) ||
    (normalized.minimumPriceMinor !== null &&
      normalized.maximumPriceMinor !== null &&
      BigInt(normalized.minimumPriceMinor) >
        BigInt(normalized.maximumPriceMinor))
  ) {
    throw new TypeError("invalid_filter_range");
  }
  return normalized;
}

function searchParameters(filters: NormalizedFilters): URLSearchParams {
  const parameters = new URLSearchParams({ page_size: "100" });
  if (filters.query) parameters.set("q", filters.query);
  if (filters.locationId) parameters.append("location_id", filters.locationId);
  if (filters.status) parameters.append("status", filters.status);
  if (filters.minimumPriceMinor)
    parameters.set("minimum_price_minor", filters.minimumPriceMinor);
  if (filters.maximumPriceMinor)
    parameters.set("maximum_price_minor", filters.maximumPriceMinor);
  if (filters.minimumAge !== null)
    parameters.set("minimum_days_in_stock", String(filters.minimumAge));
  if (filters.maximumAge !== null)
    parameters.set("maximum_days_in_stock", String(filters.maximumAge));
  return parameters;
}

function filterPreviewItems(
  items: readonly InventoryItem[],
  filters: NormalizedFilters,
): readonly InventoryItem[] {
  const query = filters.query?.toLocaleLowerCase() ?? null;
  return items.filter((item) => {
    const haystack = [
      item.stockNumber,
      item.vin,
      item.make,
      item.model,
      item.trim,
    ]
      .filter((value): value is string => value !== null)
      .join(" ")
      .toLocaleLowerCase();
    const price =
      item.advertisedPriceMinor === null
        ? null
        : BigInt(item.advertisedPriceMinor);
    return (
      (!query || haystack.includes(query)) &&
      (!filters.locationId || item.locationId === filters.locationId) &&
      (!filters.status || item.canonicalStatus === filters.status) &&
      (filters.minimumAge === null || item.daysInStock >= filters.minimumAge) &&
      (filters.maximumAge === null || item.daysInStock <= filters.maximumAge) &&
      (filters.minimumPriceMinor === null ||
        (price !== null && price >= BigInt(filters.minimumPriceMinor))) &&
      (filters.maximumPriceMinor === null ||
        (price !== null && price <= BigInt(filters.maximumPriceMinor)))
    );
  });
}

function statusLabel(copy: InventoryCopy, status: CanonicalStatus): string {
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

function vehicleLabel(item: InventoryItem, fallback: string): string {
  const value = [item.modelYear, item.make, item.model, item.trim]
    .filter((part) => part !== null)
    .join(" ");
  return value || fallback;
}

function interpolate(template: string, count: number): string {
  return template.replace("{count}", String(count));
}

function savedViewFilters(filters: NormalizedFilters): Record<string, unknown> {
  return {
    ...(filters.locationId ? { locationIds: [filters.locationId] } : {}),
    ...(filters.status ? { status: [filters.status] } : {}),
    ...(filters.minimumAge === null
      ? {}
      : { minimumDaysInStock: filters.minimumAge }),
    ...(filters.maximumAge === null
      ? {}
      : { maximumDaysInStock: filters.maximumAge }),
    ...(filters.minimumPriceMinor === null
      ? {}
      : { minimumPriceMinor: filters.minimumPriceMinor }),
    ...(filters.maximumPriceMinor === null
      ? {}
      : { maximumPriceMinor: filters.maximumPriceMinor }),
  };
}

function filtersFromSavedView(
  view: SavedInventoryView,
  currencyCode: string,
): FilterValues {
  const locationIds = Array.isArray(view.filters.locationIds)
    ? view.filters.locationIds
    : [];
  const statuses = Array.isArray(view.filters.status)
    ? view.filters.status
    : [];
  const firstLocation = locationIds.find(
    (value): value is string => typeof value === "string",
  );
  const firstStatus = statuses.find(
    (value): value is CanonicalStatus =>
      typeof value === "string" &&
      ["active", "archived", "closed", "draft", "pending"].includes(value),
  );
  const numberText = (value: unknown) =>
    typeof value === "number" && Number.isInteger(value) ? String(value) : "";
  const moneyText = (value: unknown) => {
    if (typeof value !== "string" || !/^(?:0|[1-9]\d{0,18})$/u.test(value)) {
      return "";
    }
    return minorMoneyToMajorInput(value, currencyCode);
  };
  return {
    locationId: firstLocation ?? "",
    maximumAge: numberText(view.filters.maximumDaysInStock),
    maximumPrice: moneyText(view.filters.maximumPriceMinor),
    minimumAge: numberText(view.filters.minimumDaysInStock),
    minimumPrice: moneyText(view.filters.minimumPriceMinor),
    query: "",
    status: firstStatus ?? "",
  };
}

export function InventoryWorkbench({
  copy,
  locale,
  previewMode,
}: Readonly<{
  copy: InventoryCopy;
  locale: Locale;
  previewMode: boolean;
}>) {
  const router = useRouter();
  const previewEnabled =
    process.env.NODE_ENV !== "production" && previewMode === true;
  const activeWorkspaceId = useRef("");
  const auxiliaryAbortController = useRef<AbortController | null>(null);
  const auxiliaryRequestSequence = useRef(0);
  const resultsAbortController = useRef<AbortController | null>(null);
  const resultsRequestSequence = useRef(0);
  const savedViewMutationSequence = useRef(0);
  const idempotency = useRef(
    new Map<string, Readonly<{ fingerprint: string; key: string }>>(),
  );
  const [appliedFilters, setAppliedFilters] =
    useState<FilterValues>(emptyFilters);
  const [filters, setFilters] = useState<FilterValues>(emptyFilters);
  const [filterMessage, setFilterMessage] = useState<string | null>(null);
  const [items, setItems] = useState<readonly InventoryItem[]>([]);
  const [locations, setLocations] = useState<readonly LocationOption[]>([]);
  const [phase, setPhase] = useState<LoadPhase>("loading");
  const [saveMessage, setSaveMessage] = useState<string | null>(null);
  const [savedViews, setSavedViews] = useState<readonly SavedInventoryView[]>(
    [],
  );
  const [saving, setSaving] = useState(false);
  const [selectedSavedViewId, setSelectedSavedViewId] = useState("");
  const [workspaceId, setWorkspaceId] = useState("");
  const [workspaces, setWorkspaces] = useState<readonly WorkspaceOption[]>([]);

  function commandKey(scope: string, payload: unknown): string {
    const fingerprint = JSON.stringify(payload);
    const previous = idempotency.current.get(scope);
    if (previous?.fingerprint === fingerprint) return previous.key;
    const next = { fingerprint, key: crypto.randomUUID() } as const;
    idempotency.current.set(scope, next);
    return next.key;
  }

  const loadResults = useCallback(
    async (targetWorkspaceId: string, normalized: NormalizedFilters) => {
      const sequence = ++resultsRequestSequence.current;
      resultsAbortController.current?.abort();
      const abortController = new AbortController();
      resultsAbortController.current = abortController;
      const isCurrentRequest = () =>
        activeWorkspaceId.current === targetWorkspaceId &&
        resultsRequestSequence.current === sequence &&
        !abortController.signal.aborted;
      if (!isCurrentRequest()) return;
      setPhase("loading");
      setSaveMessage(null);
      try {
        let nextItems: readonly InventoryItem[];
        if (previewEnabled) {
          nextItems = filterPreviewItems(previewItems, normalized);
          await Promise.resolve();
        } else {
          const session = (await getBrowserSupabase().auth.getSession()).data
            .session;
          if (!session) {
            router.replace("/login");
            return;
          }
          const response = await fetch(
            `/api/v1/inventory-units?${searchParameters(normalized).toString()}`,
            {
              cache: "no-store",
              headers: {
                Authorization: `Bearer ${session.access_token}`,
                "X-Correlation-Id": crypto.randomUUID(),
                "X-Request-Id": crypto.randomUUID(),
                "X-Workspace-Id": targetWorkspaceId,
              },
              signal: abortController.signal,
            },
          );
          if (!response.ok) {
            throw new TypeError("inventory_request_failed");
          }
          nextItems = parseInventoryEnvelope(await response.json());
        }

        if (isCurrentRequest()) {
          setItems(nextItems);
          setPhase(nextItems.length === 0 ? "empty" : "ready");
        }
      } catch {
        if (isCurrentRequest()) {
          setItems([]);
          setPhase("error");
        }
      }
    },
    [previewEnabled, router],
  );

  const loadAuxiliary = useCallback(
    async (targetWorkspaceId: string) => {
      const sequence = ++auxiliaryRequestSequence.current;
      auxiliaryAbortController.current?.abort();
      const abortController = new AbortController();
      auxiliaryAbortController.current = abortController;
      const isCurrentRequest = () =>
        activeWorkspaceId.current === targetWorkspaceId &&
        auxiliaryRequestSequence.current === sequence &&
        !abortController.signal.aborted;
      if (!isCurrentRequest()) return;
      if (previewEnabled) {
        await Promise.resolve();
        if (isCurrentRequest()) {
          setLocations(previewLocations);
          setSavedViews(previewSavedViews);
        }
        return;
      }
      const session = (await getBrowserSupabase().auth.getSession()).data
        .session;
      if (!session) {
        router.replace("/login");
        return;
      }
      const requestHeaders = () => ({
        Authorization: `Bearer ${session.access_token}`,
        "X-Correlation-Id": crypto.randomUUID(),
        "X-Request-Id": crypto.randomUUID(),
        "X-Workspace-Id": targetWorkspaceId,
      });
      const [locationsResponse, viewsResponse] = await Promise.all([
        fetch("/api/v1/locations", {
          cache: "no-store",
          headers: requestHeaders(),
          signal: abortController.signal,
        }),
        fetch("/api/v1/inventory-saved-views", {
          cache: "no-store",
          headers: requestHeaders(),
          signal: abortController.signal,
        }),
      ]);
      if (!locationsResponse.ok || !viewsResponse.ok) {
        throw new TypeError("inventory_auxiliary_request_failed");
      }
      const [nextLocations, nextSavedViews] = await Promise.all([
        locationsResponse.json().then(parseLocationEnvelope),
        viewsResponse.json().then(parseSavedViewsEnvelope),
      ]);
      if (isCurrentRequest()) {
        setLocations(nextLocations);
        setSavedViews(nextSavedViews);
      }
    },
    [previewEnabled, router],
  );

  useEffect(() => {
    let active = true;
    async function initialize() {
      if (previewEnabled) {
        setWorkspaces([previewWorkspace]);
        activeWorkspaceId.current = previewWorkspace.id;
        setWorkspaceId(previewWorkspace.id);
        await Promise.all([
          loadResults(
            previewWorkspace.id,
            normalizeFilters(emptyFilters, previewWorkspace.currencyCode),
          ),
          loadAuxiliary(previewWorkspace.id),
        ]);
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
          .select("id,workspaces!inner(id,name,default_currency)")
          .eq("user_id", session.user.id)
          .eq("status", "active");
        if (memberships.error) {
          throw memberships.error;
        }
        const options = parseWorkspaceOptions(memberships.data);
        const first = options[0];
        if (!first) {
          throw new TypeError("workspace_required");
        }
        initializationWorkspaceId = first.id;
        if (active) {
          setWorkspaces(options);
          activeWorkspaceId.current = first.id;
          setWorkspaceId(first.id);
          await Promise.all([
            loadResults(
              first.id,
              normalizeFilters(emptyFilters, first.currencyCode),
            ),
            loadAuxiliary(first.id),
          ]);
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
      auxiliaryAbortController.current?.abort();
      resultsAbortController.current?.abort();
    };
  }, [loadAuxiliary, loadResults, previewEnabled, router]);

  function setFilter<Key extends keyof FilterValues>(
    key: Key,
    value: FilterValues[Key],
  ) {
    setFilters((current) => ({ ...current, [key]: value }));
  }

  function applyFilters(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const currencyCode = workspaces.find(
      (option) => option.id === workspaceId,
    )?.currencyCode;
    if (!workspaceId || !currencyCode) return;
    try {
      const normalized = normalizeFilters(filters, currencyCode);
      setFilterMessage(null);
      setAppliedFilters(filters);
      void loadResults(workspaceId, normalized);
    } catch {
      setFilterMessage(copy.filterError);
    }
  }

  function clearFilters() {
    setFilters(emptyFilters);
    setAppliedFilters(emptyFilters);
    setFilterMessage(null);
    const currencyCode = workspaces.find(
      (option) => option.id === workspaceId,
    )?.currencyCode;
    if (workspaceId && currencyCode) {
      void loadResults(
        workspaceId,
        normalizeFilters(emptyFilters, currencyCode),
      );
    }
  }

  function retry() {
    const currencyCode = workspaces.find(
      (option) => option.id === workspaceId,
    )?.currencyCode;
    if (workspaceId && currencyCode) {
      void loadResults(
        workspaceId,
        normalizeFilters(appliedFilters, currencyCode),
      );
    }
  }

  async function chooseWorkspace(nextWorkspaceId: string) {
    const nextWorkspace = workspaces.find(
      (option) => option.id === nextWorkspaceId,
    );
    if (!nextWorkspace) return;
    activeWorkspaceId.current = nextWorkspaceId;
    savedViewMutationSequence.current += 1;
    setSaving(false);
    setWorkspaceId(nextWorkspaceId);
    setFilters(emptyFilters);
    setAppliedFilters(emptyFilters);
    setItems([]);
    setLocations([]);
    setSavedViews([]);
    setSaveMessage(null);
    setSelectedSavedViewId("");
    try {
      await Promise.all([
        loadResults(
          nextWorkspaceId,
          normalizeFilters(emptyFilters, nextWorkspace.currencyCode),
        ),
        loadAuxiliary(nextWorkspaceId),
      ]);
    } catch {
      if (activeWorkspaceId.current === nextWorkspaceId) setPhase("error");
    }
  }

  async function saveCurrentView() {
    const targetWorkspaceId = workspaceId;
    const currencyCode = workspaces.find(
      (option) => option.id === targetWorkspaceId,
    )?.currencyCode;
    if (
      !targetWorkspaceId ||
      activeWorkspaceId.current !== targetWorkspaceId ||
      !currencyCode
    )
      return;
    const mutationSequence = ++savedViewMutationSequence.current;
    const isCurrentMutation = () =>
      activeWorkspaceId.current === targetWorkspaceId &&
      savedViewMutationSequence.current === mutationSequence;
    setSaving(true);
    setSaveMessage(null);
    try {
      const selected = savedViews.find(
        (view) => view.savedViewId === selectedSavedViewId,
      );
      const editableView = selected?.isOwner ? selected : undefined;
      const normalized = normalizeFilters(appliedFilters, currencyCode);
      const payload = {
        density: editableView?.density ?? "comfortable",
        expectedVersion: editableView?.version ?? null,
        filters: savedViewFilters(normalized),
        layout: editableView?.layout ?? "responsive",
        name: editableView?.name ?? copy.saveViewDefaultName,
        savedViewId: editableView?.savedViewId ?? null,
        shareScope: editableView?.shareScope ?? "private",
        sort: editableView?.sort ?? { direction: "desc", key: "updated_at" },
        visibleColumns: editableView?.visibleColumns ?? [
          "stock",
          "vehicle",
          "vin",
          "price",
          "location",
          "state",
          "days_in_stock",
        ],
      } as const;
      if (previewEnabled) {
        await Promise.resolve();
        const previewView: SavedInventoryView = {
          density: payload.density,
          filters: payload.filters,
          isOwner: true,
          layout: payload.layout,
          name: payload.name,
          savedViewId: editableView?.savedViewId ?? crypto.randomUUID(),
          shareScope: payload.shareScope,
          sort: payload.sort,
          version: (editableView?.version ?? 0) + 1,
          visibleColumns: payload.visibleColumns,
        };
        if (isCurrentMutation()) {
          setSavedViews((current) => [
            previewView,
            ...current.filter(
              (view) => view.savedViewId !== previewView.savedViewId,
            ),
          ]);
          setSelectedSavedViewId(previewView.savedViewId);
        }
      } else {
        const session = (await getBrowserSupabase().auth.getSession()).data
          .session;
        if (!session) {
          router.replace("/login");
          return;
        }
        const idempotencyKey = commandKey(
          `save:${targetWorkspaceId}:${payload.savedViewId ?? "new"}`,
          payload,
        );
        const response = await fetch("/api/v1/inventory-saved-views", {
          body: JSON.stringify(payload),
          headers: {
            Authorization: `Bearer ${session.access_token}`,
            "Content-Type": "application/json",
            "Idempotency-Key": idempotencyKey,
            "X-Correlation-Id": crypto.randomUUID(),
            "X-Request-Id": crypto.randomUUID(),
            "X-Workspace-Id": targetWorkspaceId,
          },
          method: "POST",
        });
        if (!response.ok) {
          throw new TypeError("save_view_failed");
        }
        await loadAuxiliary(targetWorkspaceId);
      }
      if (isCurrentMutation()) {
        setSaveMessage(editableView ? copy.updatedView : copy.savedView);
      }
    } catch {
      if (isCurrentMutation()) setSaveMessage(copy.saveFailed);
    } finally {
      if (savedViewMutationSequence.current === mutationSequence) {
        setSaving(false);
      }
    }
  }

  function applySelectedSavedView() {
    const selected = savedViews.find(
      (view) => view.savedViewId === selectedSavedViewId,
    );
    const currencyCode = workspaces.find(
      (option) => option.id === workspaceId,
    )?.currencyCode;
    if (!selected || !workspaceId || !currencyCode) return;
    const nextFilters = filtersFromSavedView(selected, currencyCode);
    setFilters(nextFilters);
    setAppliedFilters(nextFilters);
    setFilterMessage(null);
    void loadResults(workspaceId, normalizeFilters(nextFilters, currencyCode));
  }

  async function archiveSelectedView() {
    const targetWorkspaceId = workspaceId;
    const selected = savedViews.find(
      (view) => view.savedViewId === selectedSavedViewId,
    );
    if (
      !selected?.isOwner ||
      !targetWorkspaceId ||
      activeWorkspaceId.current !== targetWorkspaceId
    )
      return;
    const mutationSequence = ++savedViewMutationSequence.current;
    const isCurrentMutation = () =>
      activeWorkspaceId.current === targetWorkspaceId &&
      savedViewMutationSequence.current === mutationSequence;
    setSaving(true);
    setSaveMessage(null);
    const payload = { expectedVersion: selected.version };
    try {
      if (previewEnabled) {
        await Promise.resolve();
        if (isCurrentMutation()) {
          setSavedViews((current) =>
            current.filter((view) => view.savedViewId !== selected.savedViewId),
          );
        }
      } else {
        const session = (await getBrowserSupabase().auth.getSession()).data
          .session;
        if (!session) {
          router.replace("/login");
          return;
        }
        const idempotencyKey = commandKey(
          `archive:${targetWorkspaceId}:${selected.savedViewId}`,
          payload,
        );
        const response = await fetch(
          `/api/v1/inventory-saved-views/${selected.savedViewId}/archive`,
          {
            body: JSON.stringify(payload),
            headers: {
              Authorization: `Bearer ${session.access_token}`,
              "Content-Type": "application/json",
              "Idempotency-Key": idempotencyKey,
              "X-Correlation-Id": crypto.randomUUID(),
              "X-Request-Id": crypto.randomUUID(),
              "X-Workspace-Id": targetWorkspaceId,
            },
            method: "POST",
          },
        );
        if (!response.ok) throw new TypeError("archive_view_failed");
        await loadAuxiliary(targetWorkspaceId);
      }
      if (isCurrentMutation()) {
        setSelectedSavedViewId("");
        setSaveMessage(copy.viewArchived);
      }
    } catch {
      if (isCurrentMutation()) setSaveMessage(copy.archiveFailed);
    } finally {
      if (savedViewMutationSequence.current === mutationSequence) {
        setSaving(false);
      }
    }
  }

  const countLabel =
    items.length === 1
      ? copy.resultsCountOne
      : interpolate(copy.resultsCount, items.length);
  const localeTag = locale === "fr" ? "fr-CA" : "en-CA";
  const returnTo = previewEnabled
    ? "/inventory?preview=inventory"
    : "/inventory";
  const newInventoryHref = previewEnabled
    ? "/inventory/new?preview=inventory"
    : "/inventory/new";
  const selectedSavedView = savedViews.find(
    (view) => view.savedViewId === selectedSavedViewId,
  );
  const inventoryNavigationQuery = [
    previewEnabled ? "preview=inventory" : null,
    workspaceId ? `workspace=${encodeURIComponent(workspaceId)}` : null,
  ]
    .filter((value): value is string => value !== null)
    .join("&");
  const inventoryHref = (inventoryUnitId: string, media = false) =>
    `/inventory/${inventoryUnitId}${media ? "/media" : ""}${
      inventoryNavigationQuery ? `?${inventoryNavigationQuery}` : ""
    }`;

  return (
    <div className="inventory-browser">
      <a className="skip-link" href="#inventory-main">
        {copy.skipToContent}
      </a>

      <header className="inventory-browser__header">
        <div className="inventory-browser__topbar">
          <a className="brand" href="/" aria-label={copy.brandHome}>
            <span className="brand-mark" aria-hidden="true">
              V
            </span>
            <span>Vynlo</span>
          </a>
          <div className="inventory-browser__controls">
            <label className="inventory-browser__workspace">
              <span className="control-label">{copy.workspaceLabel}</span>
              <select
                aria-label={copy.workspaceLabel}
                disabled={workspaces.length < 2 || saving}
                onChange={(event) => void chooseWorkspace(event.target.value)}
                value={workspaceId}
              >
                {workspaces.length === 0 ? (
                  <option value="">{copy.workspaceLoading}</option>
                ) : null}
                {workspaces.map((workspace) => (
                  <option key={workspace.id} value={workspace.id}>
                    {workspace.name}
                  </option>
                ))}
              </select>
            </label>
            <LocaleSwitcher
              activeLocale={locale}
              label={copy.localeLabel}
              localeNames={copy.localeNames}
              returnTo={returnTo}
            />
          </div>
        </div>
        <nav
          aria-label={copy.navigationLabel}
          className="inventory-browser__nav"
        >
          <a href="/">{copy.overviewNavigation}</a>
          <a aria-current="page" href="/inventory">
            {copy.inventoryNavigation}
          </a>
          <a href="/health">{copy.systemNavigation}</a>
        </nav>
      </header>

      <main
        className="inventory-browser__main"
        id="inventory-main"
        tabIndex={-1}
      >
        <header className="inventory-browser__intro">
          <div>
            {previewEnabled ? (
              <p className="inventory-browser__preview">
                {copy.developmentPreview}
              </p>
            ) : null}
            <h1>{copy.heading}</h1>
          </div>
          <div className="inventory-browser__intro-copy">
            <p>{copy.introduction}</p>
            <Button asChild>
              <a href={newInventoryHref}>
                <Plus aria-hidden="true" size={17} />
                {copy.addInventoryAction}
              </a>
            </Button>
          </div>
        </header>

        <section
          aria-labelledby="inventory-filters-heading"
          className="inventory-browser__filters"
        >
          <h2 id="inventory-filters-heading">{copy.filtersHeading}</h2>
          <form onSubmit={applyFilters}>
            <label className="inventory-browser__search">
              <span>{copy.searchLabel}</span>
              <span className="inventory-browser__search-field">
                <Search aria-hidden="true" size={18} />
                <input
                  autoComplete="off"
                  maxLength={200}
                  onChange={(event) => setFilter("query", event.target.value)}
                  placeholder={copy.searchPlaceholder}
                  type="search"
                  value={filters.query}
                />
              </span>
            </label>
            <label>
              <span>{copy.statusLabel}</span>
              <select
                onChange={(event) =>
                  setFilter(
                    "status",
                    event.target.value as FilterValues["status"],
                  )
                }
                value={filters.status}
              >
                <option value="">{copy.allStatuses}</option>
                <option value="active">{copy.activeStatus}</option>
                <option value="pending">{copy.pendingStatus}</option>
                <option value="draft">{copy.draftStatus}</option>
                <option value="closed">{copy.closedStatus}</option>
                <option value="archived">{copy.archivedStatus}</option>
              </select>
            </label>
            <label>
              <span>{copy.locationFilterLabel}</span>
              <select
                onChange={(event) =>
                  setFilter("locationId", event.target.value)
                }
                value={filters.locationId}
              >
                <option value="">{copy.allLocations}</option>
                {locations.map((location) => (
                  <option key={location.id} value={location.id}>
                    {location.name}
                  </option>
                ))}
              </select>
            </label>
            <div className="inventory-browser__saved-filter">
              <label>
                <span>{copy.savedViewsLabel}</span>
                <select
                  onChange={(event) =>
                    setSelectedSavedViewId(event.target.value)
                  }
                  value={selectedSavedViewId}
                >
                  <option value="">{copy.noSavedView}</option>
                  {savedViews.map((view) => (
                    <option key={view.savedViewId} value={view.savedViewId}>
                      {view.name}
                      {view.isOwner ? "" : ` · ${copy.sharedViewLabel}`}
                    </option>
                  ))}
                </select>
              </label>
              <div className="inventory-browser__saved-filter-actions">
                <Button
                  disabled={!selectedSavedView}
                  onClick={applySelectedSavedView}
                  type="button"
                  variant="outline"
                >
                  <Bookmark aria-hidden="true" size={17} />
                  {copy.applySavedView}
                </Button>
                {selectedSavedView?.isOwner ? (
                  <Button
                    disabled={saving}
                    onClick={() => void archiveSelectedView()}
                    type="button"
                    variant="outline"
                  >
                    <Trash2 aria-hidden="true" size={17} />
                    {copy.archiveSavedView}
                  </Button>
                ) : null}
              </div>
            </div>
            <fieldset>
              <legend>{copy.priceColumn}</legend>
              <div className="inventory-browser__range">
                <label>
                  <span>{copy.minimumPriceLabel}</span>
                  <input
                    inputMode="decimal"
                    onChange={(event) =>
                      setFilter("minimumPrice", event.target.value)
                    }
                    placeholder="0.00"
                    value={filters.minimumPrice}
                  />
                </label>
                <label>
                  <span>{copy.maximumPriceLabel}</span>
                  <input
                    inputMode="decimal"
                    onChange={(event) =>
                      setFilter("maximumPrice", event.target.value)
                    }
                    placeholder="100000.00"
                    value={filters.maximumPrice}
                  />
                </label>
              </div>
            </fieldset>
            <fieldset>
              <legend>{copy.ageLabel}</legend>
              <div className="inventory-browser__range">
                <label>
                  <span>{copy.minimumAgeLabel}</span>
                  <input
                    inputMode="numeric"
                    min="0"
                    onChange={(event) =>
                      setFilter("minimumAge", event.target.value)
                    }
                    type="number"
                    value={filters.minimumAge}
                  />
                </label>
                <label>
                  <span>{copy.maximumAgeLabel}</span>
                  <input
                    inputMode="numeric"
                    min="0"
                    onChange={(event) =>
                      setFilter("maximumAge", event.target.value)
                    }
                    type="number"
                    value={filters.maximumAge}
                  />
                </label>
              </div>
            </fieldset>
            <div className="inventory-browser__filter-actions">
              <Button
                disabled={!workspaceId || phase === "loading"}
                type="submit"
              >
                <Search aria-hidden="true" size={17} />
                {copy.applyFilters}
              </Button>
              <Button onClick={clearFilters} type="button" variant="outline">
                <RotateCcw aria-hidden="true" size={17} />
                {copy.clearFilters}
              </Button>
            </div>
          </form>
          {filterMessage ? (
            <p className="inventory-browser__filter-error" role="alert">
              {filterMessage}
            </p>
          ) : null}
        </section>

        <section
          aria-busy={phase === "loading"}
          aria-labelledby="inventory-results-heading"
          className="inventory-browser__results"
        >
          <header className="inventory-browser__results-header">
            <div>
              <h2 id="inventory-results-heading">{copy.resultsHeading}</h2>
              <p aria-live="polite">{phase === "loading" ? "" : countLabel}</p>
            </div>
            <div className="inventory-browser__save-view">
              <Button
                disabled={!workspaceId || phase === "loading" || saving}
                onClick={() => void saveCurrentView()}
                type="button"
                variant="outline"
              >
                {saving ? (
                  <LoaderCircle
                    aria-hidden="true"
                    className="inventory-browser__spinner"
                    size={17}
                  />
                ) : (
                  <Bookmark aria-hidden="true" size={17} />
                )}
                {saving
                  ? copy.savingView
                  : selectedSavedView?.isOwner
                    ? copy.updateSavedView
                    : copy.saveViewAction}
              </Button>
              <p aria-live="polite">{saveMessage}</p>
            </div>
          </header>

          {phase === "loading" ? (
            <div className="inventory-browser__state" role="status">
              <LoaderCircle
                aria-hidden="true"
                className="inventory-browser__spinner"
                size={26}
              />
              <div>
                <h3>{copy.loadingHeading}</h3>
                <p>{copy.loadingDescription}</p>
              </div>
            </div>
          ) : null}

          {phase === "empty" ? (
            <div className="inventory-browser__state" role="status">
              <Search aria-hidden="true" size={26} />
              <div>
                <h3>{copy.emptyHeading}</h3>
                <p>{copy.emptyDescription}</p>
              </div>
            </div>
          ) : null}

          {phase === "error" ? (
            <div
              className="inventory-browser__state inventory-browser__state--error"
              role="alert"
            >
              <CircleAlert aria-hidden="true" size={26} />
              <div>
                <h3>{copy.unavailableHeading}</h3>
                <p>{copy.unavailableDescription}</p>
                <Button onClick={retry} type="button" variant="outline">
                  <RotateCcw aria-hidden="true" size={17} />
                  {copy.retryAction}
                </Button>
              </div>
            </div>
          ) : null}

          {phase === "ready" ? (
            <>
              <ul
                aria-label={copy.resultsLabel}
                className="inventory-browser__cards"
              >
                {items.map((item) => (
                  <li key={item.inventoryUnitId}>
                    <article>
                      <header>
                        <div>
                          <p>{item.stockNumber}</p>
                          <h3>{vehicleLabel(item, copy.unknownVehicle)}</h3>
                        </div>
                        <span data-status={item.canonicalStatus}>
                          {statusLabel(copy, item.canonicalStatus)}
                        </span>
                      </header>
                      <dl>
                        <div>
                          <dt>{copy.priceColumn}</dt>
                          <dd>
                            {item.advertisedPriceMinor === null
                              ? copy.priceUnavailable
                              : formatMinorMoney(
                                  item.advertisedPriceMinor,
                                  item.currencyCode,
                                  localeTag,
                                )}
                          </dd>
                        </div>
                        <div>
                          <dt>{copy.ageLabel}</dt>
                          <dd>
                            {interpolate(copy.daysInStock, item.daysInStock)}
                          </dd>
                        </div>
                        <div>
                          <dt>{copy.locationColumn}</dt>
                          <dd>{item.locationName ?? copy.noLocation}</dd>
                        </div>
                        <div>
                          <dt>{copy.vinColumn}</dt>
                          <dd className="inventory-browser__vin">{item.vin}</dd>
                        </div>
                      </dl>
                      <footer className="inventory-browser__item-actions">
                        <a href={inventoryHref(item.inventoryUnitId)}>
                          <Eye aria-hidden="true" size={17} />
                          {copy.openDetailsAction}
                        </a>
                        <a href={inventoryHref(item.inventoryUnitId, true)}>
                          <Images aria-hidden="true" size={17} />
                          {copy.managePhotosAction}
                        </a>
                      </footer>
                    </article>
                  </li>
                ))}
              </ul>

              <div className="inventory-browser__table-wrap">
                <table aria-label={copy.resultsLabel}>
                  <thead>
                    <tr>
                      <th scope="col">{copy.stockColumn}</th>
                      <th scope="col">{copy.vehicleColumn}</th>
                      <th scope="col">{copy.vinColumn}</th>
                      <th scope="col">{copy.priceColumn}</th>
                      <th scope="col">{copy.locationColumn}</th>
                      <th scope="col">{copy.stateColumn}</th>
                      <th scope="col">{copy.ageLabel}</th>
                      <th scope="col">{copy.actionsColumn}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {items.map((item) => (
                      <tr key={item.inventoryUnitId}>
                        <td>
                          <strong>{item.stockNumber}</strong>
                        </td>
                        <td>{vehicleLabel(item, copy.unknownVehicle)}</td>
                        <td className="inventory-browser__vin">{item.vin}</td>
                        <td>
                          {item.advertisedPriceMinor === null
                            ? copy.priceUnavailable
                            : formatMinorMoney(
                                item.advertisedPriceMinor,
                                item.currencyCode,
                                localeTag,
                              )}
                        </td>
                        <td>{item.locationName ?? copy.noLocation}</td>
                        <td>
                          <span
                            className="inventory-browser__status"
                            data-status={item.canonicalStatus}
                          >
                            {statusLabel(copy, item.canonicalStatus)}
                          </span>
                        </td>
                        <td>
                          {interpolate(copy.daysInStock, item.daysInStock)}
                        </td>
                        <td>
                          <span className="inventory-browser__row-actions">
                            <a href={inventoryHref(item.inventoryUnitId)}>
                              {copy.openDetailsAction}
                            </a>
                            <a href={inventoryHref(item.inventoryUnitId, true)}>
                              {copy.managePhotosAction}
                            </a>
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          ) : null}
        </section>
      </main>
    </div>
  );
}
