"use client";

import {
  isPlatformPermissionKey,
  type PlatformPermissionKey,
} from "@vynlo/auth";
import { Button } from "@vynlo/ui-web/components/button";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  Check,
  FileText,
  LogOut,
  MailPlus,
  PackagePlus,
  ShieldCheck,
  Users,
} from "lucide-react";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import { getBrowserSupabase } from "../lib/supabase-browser";
import { parseMoneyMinorInput } from "../lib/money";

interface OperationsCopy {
  readonly authRequired: string;
  readonly backAction: string;
  readonly commandFailed: string;
  readonly currencyLabel: string;
  readonly dealAction: string;
  readonly dealHeading: string;
  readonly dealTypeLabel: string;
  readonly displayNameLabel: string;
  readonly emptyRows: string;
  readonly inventoryAction: string;
  readonly inventoryEmpty: string;
  readonly inventoryHeading: string;
  readonly inventoryRecentHeading: string;
  readonly inventoryStatusArchived: string;
  readonly inventoryStatusClosed: string;
  readonly inventoryStatusDraft: string;
  readonly inventoryStatusActive: string;
  readonly inventoryStatusLabel: string;
  readonly inventoryStatusUnknown: string;
  readonly inviteAction: string;
  readonly inviteEmailLabel: string;
  readonly inviteExpiry: string;
  readonly inviteHeading: string;
  readonly inviteLocaleLabel: string;
  readonly inviteQueued: string;
  readonly inviteRolesLabel: string;
  readonly localeLabel: string;
  readonly makeLabel: string;
  readonly mfaCodeLabel: string;
  readonly mfaEnrollAction: string;
  readonly mfaHeading: string;
  readonly mfaIntroduction: string;
  readonly mfaSecretLabel: string;
  readonly mfaVerifyAction: string;
  readonly modelLabel: string;
  readonly modelYearLabel: string;
  readonly odometerLabel: string;
  readonly openPreviewAction: string;
  readonly organizationOption: string;
  readonly partyAction: string;
  readonly partyHeading: string;
  readonly partyTypeLabel: string;
  readonly personOption: string;
  readonly permissionDenied: string;
  readonly previewAction: string;
  readonly previewHeading: string;
  readonly previewQueued: string;
  readonly previewUnavailable: string;
  readonly priceLabel: string;
  readonly recentHeading: string;
  readonly sessionHeading: string;
  readonly signOutAction: string;
  readonly stage: string;
  readonly statusFailed: string;
  readonly statusGenerated: string;
  readonly statusQueued: string;
  readonly stockLabel: string;
  readonly vinLabel: string;
  readonly working: string;
  readonly workspaceLabel: string;
}

interface WorkspaceOption {
  readonly currencyCode: string;
  readonly id: string;
  readonly locale: string;
  readonly membershipId: string;
  readonly name: string;
  readonly odometerUnit: "km" | "mi";
}

interface InventoryRow {
  readonly id: string;
  readonly stockNumber: string;
  readonly status: string;
}

interface PartyRow {
  readonly displayName: string;
  readonly id: string;
  readonly partyType: string;
}

interface DealRow {
  readonly id: string;
  readonly status: string;
}

interface RoleOption {
  readonly id: string;
  readonly name: string;
}

interface DocumentRow {
  readonly artifact: Readonly<{
    bucket: string;
    objectPath: string;
  }> | null;
  readonly id: string;
  readonly status: string;
  readonly watermark: string;
}

interface WorkspaceResources {
  readonly deals: readonly DealRow[];
  readonly documents: readonly DocumentRow[];
  readonly inventory: readonly InventoryRow[];
  readonly parties: readonly PartyRow[];
  readonly permissions: ReadonlySet<PlatformPermissionKey>;
  readonly roles: readonly RoleOption[];
  readonly stockDefinitionId: string | null;
  readonly templateVersionId: string | null;
}

const emptyResources: WorkspaceResources = {
  deals: [],
  documents: [],
  inventory: [],
  parties: [],
  permissions: new Set(),
  roles: [],
  stockDefinitionId: null,
  templateVersionId: null,
};

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function rows(value: unknown): readonly Record<string, unknown>[] {
  return Array.isArray(value)
    ? value.flatMap((item) => {
        const parsed = record(item);
        return parsed ? [parsed] : [];
      })
    : [];
}

function stringField(
  source: Record<string, unknown>,
  key: string,
): string | null {
  const value = source[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function parseWorkspaceRows(value: unknown): readonly WorkspaceOption[] {
  return rows(value).flatMap((membership) => {
    const workspaceRelation = membership.workspaces;
    const workspace = Array.isArray(workspaceRelation)
      ? record(workspaceRelation[0])
      : record(workspaceRelation);
    const membershipId = stringField(membership, "id");
    const id = workspace ? stringField(workspace, "id") : null;
    const name = workspace ? stringField(workspace, "name") : null;
    const locale = workspace ? stringField(workspace, "default_locale") : null;
    const currencyCode = workspace
      ? stringField(workspace, "default_currency")
      : null;
    const odometerUnit = workspace
      ? stringField(workspace, "odometer_unit")
      : null;

    return membershipId &&
      id &&
      name &&
      locale &&
      currencyCode &&
      (odometerUnit === "km" || odometerUnit === "mi")
      ? [{ currencyCode, id, locale, membershipId, name, odometerUnit }]
      : [];
  });
}

async function loadWorkspaceOptions(
  client: SupabaseClient,
  userId: string,
): Promise<readonly WorkspaceOption[]> {
  const membershipResult = await client
    .from("workspace_memberships")
    .select(
      "id,workspace_id,workspaces!inner(id,name,default_locale,default_currency,odometer_unit)",
    )
    .eq("user_id", userId)
    .eq("status", "active");
  if (membershipResult.error) {
    throw new TypeError("workspace_membership_load_failed");
  }
  return parseWorkspaceRows(membershipResult.data);
}

function commandId(data: unknown, camelKey: string, snakeKey: string): string {
  const source = record(data);
  const value = source
    ? (stringField(source, camelKey) ?? stringField(source, snakeKey))
    : null;
  if (!value) {
    throw new TypeError("invalid_command_response");
  }
  return value;
}

function inventoryStatusLabel(copy: OperationsCopy, status: string): string {
  switch (status) {
    case "active":
      return copy.inventoryStatusActive;
    case "archived":
      return copy.inventoryStatusArchived;
    case "closed":
      return copy.inventoryStatusClosed;
    case "draft":
      return copy.inventoryStatusDraft;
    default:
      return copy.inventoryStatusUnknown;
  }
}

async function loadPermissions(
  client: SupabaseClient,
  workspace: WorkspaceOption,
): Promise<ReadonlySet<PlatformPermissionKey>> {
  const roleResult = await client
    .from("membership_roles")
    .select("role_id")
    .eq("workspace_id", workspace.id)
    .eq("membership_id", workspace.membershipId)
    .eq("status", "active");
  if (roleResult.error) {
    return new Set();
  }
  const roleIds = rows(roleResult.data).flatMap((item) => {
    const id = stringField(item, "role_id");
    return id ? [id] : [];
  });
  if (roleIds.length === 0) {
    return new Set();
  }

  const grantResult = await client
    .from("role_permissions")
    .select("permission_id")
    .eq("workspace_id", workspace.id)
    .eq("status", "active")
    .in("role_id", roleIds);
  if (grantResult.error) {
    return new Set();
  }
  const permissionIds = rows(grantResult.data).flatMap((item) => {
    const id = stringField(item, "permission_id");
    return id ? [id] : [];
  });
  if (permissionIds.length === 0) {
    return new Set();
  }

  const permissionResult = await client
    .from("permissions")
    .select("key")
    .in("id", permissionIds);
  return new Set(
    rows(permissionResult.data).flatMap((item) => {
      const key = stringField(item, "key");
      return isPlatformPermissionKey(key) ? [key] : [];
    }),
  );
}

async function loadWorkspaceResources(
  client: SupabaseClient,
  workspace: WorkspaceOption,
): Promise<WorkspaceResources> {
  const [
    permissions,
    stockResult,
    templateResult,
    inventoryResult,
    partyResult,
    dealResult,
    documentResult,
    artifactResult,
    roleResult,
  ] = await Promise.all([
    loadPermissions(client, workspace),
    client
      .from("stock_number_definitions")
      .select("id")
      .eq("workspace_id", workspace.id)
      .eq("status", "active")
      .order("version", { ascending: false })
      .limit(1),
    client
      .from("document_template_versions")
      .select("id")
      .eq("workspace_id", workspace.id)
      .eq("status", "active")
      .order("version", { ascending: false })
      .limit(1),
    client
      .from("inventory_units")
      .select("id,stock_number,status")
      .eq("workspace_id", workspace.id)
      .order("created_at", { ascending: false })
      .limit(20),
    client
      .from("parties")
      .select("id,party_type,display_name")
      .eq("workspace_id", workspace.id)
      .order("created_at", { ascending: false })
      .limit(20),
    client
      .from("deals")
      .select("id,status")
      .eq("workspace_id", workspace.id)
      .order("created_at", { ascending: false })
      .limit(20),
    client
      .from("documents")
      .select("id,status,watermark")
      .eq("workspace_id", workspace.id)
      .order("created_at", { ascending: false })
      .limit(20),
    client
      .from("document_preview_artifacts")
      .select("document_id,storage_bucket,storage_object_path")
      .eq("workspace_id", workspace.id),
    client
      .from("roles")
      .select("id,name")
      .eq("workspace_id", workspace.id)
      .eq("status", "active")
      .order("name"),
  ]);

  const stockDefinitionId = stringField(rows(stockResult.data)[0] ?? {}, "id");
  const templateVersionId = stringField(
    rows(templateResult.data)[0] ?? {},
    "id",
  );
  const artifactsByDocument = new Map(
    rows(artifactResult.data).flatMap((item) => {
      const documentId = stringField(item, "document_id");
      const bucket = stringField(item, "storage_bucket");
      const objectPath = stringField(item, "storage_object_path");
      return documentId && bucket && objectPath
        ? [[documentId, { bucket, objectPath }] as const]
        : [];
    }),
  );

  return {
    deals: rows(dealResult.data).flatMap((item) => {
      const id = stringField(item, "id");
      const status = stringField(item, "status");
      return id && status ? [{ id, status }] : [];
    }),
    documents: rows(documentResult.data).flatMap((item) => {
      const id = stringField(item, "id");
      const status = stringField(item, "status");
      const watermark = stringField(item, "watermark");
      return id && status && watermark
        ? [
            {
              artifact: artifactsByDocument.get(id) ?? null,
              id,
              status,
              watermark,
            },
          ]
        : [];
    }),
    inventory: rows(inventoryResult.data).flatMap((item) => {
      const id = stringField(item, "id");
      const stockNumber = stringField(item, "stock_number");
      const status = stringField(item, "status");
      return id && stockNumber && status ? [{ id, status, stockNumber }] : [];
    }),
    parties: rows(partyResult.data).flatMap((item) => {
      const id = stringField(item, "id");
      const partyType = stringField(item, "party_type");
      const displayName = stringField(item, "display_name");
      return id && partyType && displayName
        ? [{ displayName, id, partyType }]
        : [];
    }),
    permissions,
    roles: rows(roleResult.data).flatMap((item) => {
      const id = stringField(item, "id");
      const name = stringField(item, "name");
      return id && name ? [{ id, name }] : [];
    }),
    stockDefinitionId,
    templateVersionId,
  };
}

export function OperationsWorkbench({
  copy,
}: Readonly<{ copy: OperationsCopy }>) {
  const router = useRouter();
  const idempotency = useRef(
    new Map<string, Readonly<{ fingerprint: string; key: string }>>(),
  );
  const [busy, setBusy] = useState<string | null>(null);
  const [configured, setConfigured] = useState(true);
  const [mfaCode, setMfaCode] = useState("");
  const [mfaFactorId, setMfaFactorId] = useState<string | null>(null);
  const [mfaQrCode, setMfaQrCode] = useState<string | null>(null);
  const [mfaSecret, setMfaSecret] = useState<string | null>(null);
  const [mfaVerified, setMfaVerified] = useState(false);
  const [resources, setResources] = useState(emptyResources);
  const [selectedWorkspaceId, setSelectedWorkspaceId] = useState("");
  const [status, setStatus] = useState<string | null>(null);
  const [workspaces, setWorkspaces] = useState<readonly WorkspaceOption[]>([]);

  const workspace = workspaces.find((item) => item.id === selectedWorkspaceId);

  const refreshResources = useCallback(async (target: WorkspaceOption) => {
    const client = getBrowserSupabase();
    const nextResources = await loadWorkspaceResources(client, target);
    setResources(nextResources);
  }, []);

  useEffect(() => {
    async function initialize() {
      try {
        const client = getBrowserSupabase();
        const sessionResult = await client.auth.getSession();
        const session = sessionResult.data.session;
        if (!session) {
          router.replace("/login");
          return;
        }

        const assurance =
          await client.auth.mfa.getAuthenticatorAssuranceLevel();
        setMfaVerified(assurance.data?.currentLevel === "aal2");
        const factors = await client.auth.mfa.listFactors();
        const verifiedFactor = factors.data?.totp.find(
          (factor) => factor.status === "verified",
        );
        if (verifiedFactor) {
          setMfaFactorId(verifiedFactor.id);
        }

        const options = await loadWorkspaceOptions(client, session.user.id);
        setWorkspaces(options);
        const first = options[0];
        if (first) {
          setSelectedWorkspaceId(first.id);
          if (assurance.data?.currentLevel === "aal2") {
            await refreshResources(first);
          }
        }
      } catch {
        setConfigured(false);
        setStatus(copy.authRequired);
        router.replace("/login");
      }
    }

    void initialize();
  }, [copy.authRequired, refreshResources, router]);

  useEffect(() => {
    if (
      !mfaVerified ||
      !workspace ||
      !resources.documents.some((document) => document.status === "queued")
    ) {
      return;
    }
    const timer = window.setInterval(() => {
      void refreshResources(workspace).catch(() => undefined);
    }, 3_000);
    return () => window.clearInterval(timer);
  }, [mfaVerified, refreshResources, resources.documents, workspace]);

  async function enrollMfa() {
    setBusy("mfa");
    setStatus(null);
    try {
      const result = await getBrowserSupabase().auth.mfa.enroll({
        factorType: "totp",
        friendlyName: "Vynlo authenticator",
      });
      if (result.error) {
        throw result.error;
      }
      setMfaFactorId(result.data.id);
      setMfaQrCode(result.data.totp.qr_code);
      setMfaSecret(result.data.totp.secret);
    } catch {
      setStatus(copy.commandFailed);
    } finally {
      setBusy(null);
    }
  }

  async function verifyMfa(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!mfaFactorId) {
      return;
    }
    setBusy("mfa");
    setStatus(null);
    try {
      const client = getBrowserSupabase();
      const result = await client.auth.mfa.challengeAndVerify({
        code: mfaCode.trim(),
        factorId: mfaFactorId,
      });
      if (result.error) {
        throw result.error;
      }
      const session = (await client.auth.getSession()).data.session;
      if (!session) {
        throw new TypeError("verified_session_required");
      }
      const options = await loadWorkspaceOptions(client, session.user.id);
      const selected =
        options.find((item) => item.id === selectedWorkspaceId) ?? options[0];
      if (!selected) {
        throw new TypeError("verified_workspace_required");
      }
      setWorkspaces(options);
      setSelectedWorkspaceId(selected.id);
      await refreshResources(selected);
      setMfaCode("");
      setMfaVerified(true);
    } catch {
      setStatus(copy.commandFailed);
    } finally {
      setBusy(null);
    }
  }

  async function chooseWorkspace(workspaceId: string) {
    setSelectedWorkspaceId(workspaceId);
    const selected = workspaces.find((item) => item.id === workspaceId);
    if (selected && mfaVerified) {
      setBusy("workspace");
      try {
        await refreshResources(selected);
      } finally {
        setBusy(null);
      }
    }
  }

  function idempotencyKey(scope: string, payload: unknown): string {
    const fingerprint = JSON.stringify(payload);
    const previous = idempotency.current.get(scope);
    if (previous?.fingerprint === fingerprint) {
      return previous.key;
    }
    const next = { fingerprint, key: crypto.randomUUID() } as const;
    idempotency.current.set(scope, next);
    return next.key;
  }

  async function command(
    scope: string,
    path: string,
    payload: Readonly<Record<string, unknown>>,
  ): Promise<unknown> {
    if (!workspace) {
      throw new TypeError("workspace_required");
    }
    const client = getBrowserSupabase();
    const session = (await client.auth.getSession()).data.session;
    if (!session) {
      router.replace("/login");
      throw new TypeError("session_required");
    }
    const correlationId = crypto.randomUUID();
    const response = await fetch(path, {
      body: JSON.stringify(payload),
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        "Content-Type": "application/json",
        "Idempotency-Key": idempotencyKey(scope, payload),
        "X-Correlation-Id": correlationId,
        "X-Request-Id": crypto.randomUUID(),
        "X-Workspace-Id": workspace.id,
      },
      method: "POST",
    });
    const envelope: unknown = await response.json();
    if (!response.ok) {
      const error = record(record(envelope)?.error);
      const code = error ? stringField(error, "code") : null;
      throw new TypeError(code ?? "command_failed");
    }
    idempotency.current.delete(scope);
    return record(envelope)?.data;
  }

  async function runCommand(
    scope: string,
    path: string,
    payload: Readonly<Record<string, unknown>>,
  ) {
    setBusy(scope);
    setStatus(null);
    try {
      const data = await command(scope, path, payload);
      if (workspace) {
        await refreshResources(workspace);
      }
      return data;
    } catch (error) {
      setStatus(
        error instanceof TypeError && error.message.includes("permission")
          ? copy.permissionDenied
          : copy.commandFailed,
      );
      return null;
    } finally {
      setBusy(null);
    }
  }

  async function createInventory(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formElement = event.currentTarget;
    if (!workspace || !resources.stockDefinitionId) {
      setStatus(copy.commandFailed);
      return;
    }
    const form = new FormData(formElement);
    let advertisedPriceMinor: number | null;
    try {
      advertisedPriceMinor = parseMoneyMinorInput(
        String(form.get("price") ?? ""),
      );
    } catch {
      setStatus(copy.commandFailed);
      return;
    }
    const modelYearValue = String(form.get("modelYear") ?? "").trim();
    const odometerValue = String(form.get("odometer") ?? "").trim();
    const data = await runCommand("inventory", "/api/v1/inventory-units", {
      acquisitionDate: null,
      advertisedPriceMinor,
      currencyCode: workspace.currencyCode,
      make: String(form.get("make") ?? "") || null,
      model: String(form.get("model") ?? "") || null,
      modelYear: modelYearValue ? Number(modelYearValue) : null,
      odometer: odometerValue
        ? { unit: workspace.odometerUnit, value: Number(odometerValue) }
        : null,
      publicNotes: null,
      stockNumberDefinitionId: resources.stockDefinitionId,
      vin: String(form.get("vin") ?? ""),
    });
    if (data) {
      setStatus(
        `${copy.stockLabel}: ${commandId(data, "stockNumber", "stock_number")}`,
      );
      formElement.reset();
    }
  }

  async function createParty(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
    const data = await runCommand("party", "/api/v1/parties", {
      displayName: String(form.get("displayName") ?? ""),
      partyType: String(form.get("partyType") ?? "person"),
    });
    if (data) {
      setStatus(copy.partyHeading);
      formElement.reset();
    }
  }

  async function createInvitation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
    const roleIds = form
      .getAll("roleId")
      .map(String)
      .filter((value) => resources.roles.some((role) => role.id === value));
    if (roleIds.length === 0) {
      setStatus(copy.commandFailed);
      return;
    }
    const data = await runCommand(
      "workspace-invitation",
      "/api/v1/workspace-invitations",
      {
        email: String(form.get("email") ?? ""),
        expiresAt: new Date(
          Date.now() + 7 * 24 * 60 * 60 * 1_000,
        ).toISOString(),
        requestedLocale: String(form.get("requestedLocale") ?? "en-CA"),
        roleIds,
      },
    );
    if (data) {
      setStatus(copy.inviteQueued);
      formElement.reset();
    }
  }

  async function createDeal(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!workspace) {
      return;
    }
    const form = new FormData(event.currentTarget);
    const data = await runCommand("deal", "/api/v1/deals", {
      currencyCode: workspace.currencyCode,
      dealTypeKey: String(form.get("dealType") ?? "retail.cash"),
      inventory: {
        inventoryUnitId: String(form.get("inventoryUnitId") ?? ""),
        roleKey: "sold",
      },
      notes: null,
      participant: {
        partyId: String(form.get("partyId") ?? ""),
        roleKey: "customer.primary",
      },
    });
    if (data) {
      setStatus(`${copy.dealHeading}: ${commandId(data, "dealId", "deal_id")}`);
    }
  }

  async function requestPreview(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!workspace || !resources.templateVersionId) {
      return;
    }
    const form = new FormData(event.currentTarget);
    const data = await runCommand("preview", "/api/v1/documents/preview", {
      dealId: String(form.get("dealId") ?? ""),
      locale: workspace.locale,
      templateVersionId: resources.templateVersionId,
    });
    if (data) {
      setStatus(copy.previewQueued);
    }
  }

  async function signOut() {
    await getBrowserSupabase().auth.signOut({ scope: "local" });
    router.replace("/login");
  }

  async function openPreview(document: DocumentRow) {
    if (!document.artifact) {
      setStatus(copy.previewUnavailable);
      return;
    }
    setBusy(`open:${document.id}`);
    const previewWindow = window.open("about:blank", "_blank");
    if (previewWindow) {
      previewWindow.opener = null;
    }
    try {
      const result = await getBrowserSupabase()
        .storage.from(document.artifact.bucket)
        .createSignedUrl(document.artifact.objectPath, 60);
      if (result.error) {
        throw result.error;
      }
      if (!previewWindow) {
        throw new TypeError("preview_window_blocked");
      }
      previewWindow.location.replace(result.data.signedUrl);
    } catch {
      previewWindow?.close();
      setStatus(copy.previewUnavailable);
    } finally {
      setBusy(null);
    }
  }

  const can = (permission: PlatformPermissionKey) =>
    resources.permissions.has(permission);

  return (
    <div className="operations-shell">
      <header className="operations-header">
        <div>
          <p className="eyebrow">
            <span>{copy.stage}</span>
          </p>
          <h1>{copy.sessionHeading}</h1>
          <a className="back-link" href="/">
            {copy.backAction}
          </a>
        </div>
        <Button onClick={signOut} size="sm" type="button" variant="outline">
          <LogOut aria-hidden="true" size={16} /> {copy.signOutAction}
        </Button>
      </header>

      {!mfaVerified ? (
        <section aria-labelledby="mfa-title" className="mfa-gate">
          <ShieldCheck aria-hidden="true" size={28} />
          <div>
            <h1 id="mfa-title">{copy.mfaHeading}</h1>
            <p>{copy.mfaIntroduction}</p>
          </div>
          {!mfaFactorId ? (
            <Button
              disabled={!configured || busy === "mfa"}
              onClick={enrollMfa}
              type="button"
            >
              {busy === "mfa" ? copy.working : copy.mfaEnrollAction}
            </Button>
          ) : null}
          {mfaQrCode ? (
            <div className="mfa-enrollment">
              {/* QR data is generated by the configured Supabase Auth project. */}
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img alt="" height="192" src={mfaQrCode} width="192" />
              <p>
                <strong>{copy.mfaSecretLabel}</strong>
                <code>{mfaSecret}</code>
              </p>
            </div>
          ) : null}
          {mfaFactorId ? (
            <form className="mfa-verify" onSubmit={verifyMfa}>
              <label>
                <span>{copy.mfaCodeLabel}</span>
                <input
                  autoComplete="one-time-code"
                  inputMode="numeric"
                  maxLength={8}
                  onChange={(event) => setMfaCode(event.target.value)}
                  pattern="[0-9]{6,8}"
                  required
                  value={mfaCode}
                />
              </label>
              <Button disabled={busy === "mfa"} type="submit">
                {busy === "mfa" ? copy.working : copy.mfaVerifyAction}
              </Button>
            </form>
          ) : null}
        </section>
      ) : (
        <>
          <section className="workspace-context">
            <label>
              <span>{copy.workspaceLabel}</span>
              <select
                disabled={!configured || busy === "workspace"}
                onChange={(event) => chooseWorkspace(event.target.value)}
                value={selectedWorkspaceId}
              >
                {workspaces.map((option) => (
                  <option key={option.id} value={option.id}>
                    {option.name}
                  </option>
                ))}
              </select>
            </label>
            <p>
              <Check aria-hidden="true" size={16} /> {copy.localeLabel}:{" "}
              {workspace?.locale} · {copy.currencyLabel}:{" "}
              {workspace?.currencyCode}
            </p>
          </section>

          {can("users.manage") ? (
            <section
              aria-labelledby="invitation-title"
              className="invitation-panel"
            >
              <div className="invitation-panel__heading">
                <span className="step-icon">
                  <MailPlus aria-hidden="true" />
                </span>
                <div>
                  <p className="step-number">ACCESS</p>
                  <h2 id="invitation-title">{copy.inviteHeading}</h2>
                  <p>{copy.inviteExpiry}</p>
                </div>
              </div>
              <form onSubmit={createInvitation}>
                <label>
                  <span>{copy.inviteEmailLabel}</span>
                  <input
                    autoComplete="email"
                    inputMode="email"
                    maxLength={254}
                    name="email"
                    required
                    type="email"
                  />
                </label>
                <label>
                  <span>{copy.inviteLocaleLabel}</span>
                  <select
                    defaultValue={
                      workspace?.locale.toLowerCase().startsWith("fr")
                        ? "fr-CA"
                        : "en-CA"
                    }
                    name="requestedLocale"
                  >
                    <option value="en-CA">English (Canada)</option>
                    <option value="fr-CA">Français (Canada)</option>
                  </select>
                </label>
                <fieldset>
                  <legend>{copy.inviteRolesLabel}</legend>
                  <div className="role-options">
                    {resources.roles.map((role) => (
                      <label key={role.id}>
                        <input name="roleId" type="checkbox" value={role.id} />
                        <span>{role.name}</span>
                      </label>
                    ))}
                  </div>
                </fieldset>
                <Button
                  disabled={
                    busy === "workspace-invitation" ||
                    resources.roles.length === 0
                  }
                  type="submit"
                >
                  {busy === "workspace-invitation"
                    ? copy.working
                    : copy.inviteAction}
                </Button>
              </form>
            </section>
          ) : null}

          <div className="workflow-grid">
            <section aria-labelledby="inventory-step" className="workflow-step">
              <span className="step-icon">
                <PackagePlus aria-hidden="true" />
              </span>
              <div>
                <p className="step-number">01</p>
                <h2 id="inventory-step">{copy.inventoryHeading}</h2>
              </div>
              <form onSubmit={createInventory}>
                <label>
                  <span>{copy.vinLabel}</span>
                  <input
                    defaultValue="1M8GDM9AXKP042788"
                    maxLength={17}
                    name="vin"
                    required
                  />
                </label>
                <div className="field-pair">
                  <label>
                    <span>{copy.modelYearLabel}</span>
                    <input
                      inputMode="numeric"
                      max="2200"
                      min="1886"
                      name="modelYear"
                      type="number"
                    />
                  </label>
                  <label>
                    <span>{copy.odometerLabel}</span>
                    <input
                      inputMode="numeric"
                      min="0"
                      name="odometer"
                      type="number"
                    />
                  </label>
                </div>
                <div className="field-pair">
                  <label>
                    <span>{copy.makeLabel}</span>
                    <input maxLength={100} name="make" />
                  </label>
                  <label>
                    <span>{copy.modelLabel}</span>
                    <input maxLength={100} name="model" />
                  </label>
                </div>
                <label>
                  <span>{copy.priceLabel}</span>
                  <input
                    inputMode="decimal"
                    name="price"
                    placeholder="12500.00"
                  />
                </label>
                <Button
                  disabled={
                    !can("inventory.create") ||
                    busy === "inventory" ||
                    !resources.stockDefinitionId
                  }
                  type="submit"
                >
                  {busy === "inventory" ? copy.working : copy.inventoryAction}
                </Button>
              </form>
            </section>

            <section aria-labelledby="party-step" className="workflow-step">
              <span className="step-icon">
                <Users aria-hidden="true" />
              </span>
              <div>
                <p className="step-number">02</p>
                <h2 id="party-step">{copy.partyHeading}</h2>
              </div>
              <form onSubmit={createParty}>
                <label>
                  <span>{copy.partyTypeLabel}</span>
                  <select defaultValue="person" name="partyType">
                    <option value="person">{copy.personOption}</option>
                    <option value="organization">
                      {copy.organizationOption}
                    </option>
                  </select>
                </label>
                <label>
                  <span>{copy.displayNameLabel}</span>
                  <input maxLength={200} name="displayName" required />
                </label>
                <Button
                  disabled={!can("crm.create") || busy === "party"}
                  type="submit"
                >
                  {busy === "party" ? copy.working : copy.partyAction}
                </Button>
              </form>
            </section>

            <section aria-labelledby="deal-step" className="workflow-step">
              <span className="step-icon">
                <FileText aria-hidden="true" />
              </span>
              <div>
                <p className="step-number">03</p>
                <h2 id="deal-step">{copy.dealHeading}</h2>
              </div>
              <form onSubmit={createDeal}>
                <label>
                  <span>{copy.dealTypeLabel}</span>
                  <input defaultValue="retail.cash" name="dealType" required />
                </label>
                <label>
                  <span>{copy.partyHeading}</span>
                  <select name="partyId" required>
                    {resources.parties.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.displayName}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  <span>{copy.inventoryHeading}</span>
                  <select name="inventoryUnitId" required>
                    {resources.inventory.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.stockNumber}
                      </option>
                    ))}
                  </select>
                </label>
                <Button
                  disabled={
                    !can("deals.create") ||
                    busy === "deal" ||
                    resources.parties.length === 0 ||
                    resources.inventory.length === 0
                  }
                  type="submit"
                >
                  {busy === "deal" ? copy.working : copy.dealAction}
                </Button>
              </form>
            </section>

            <section
              aria-labelledby="preview-step"
              className="workflow-step workflow-step--signal"
            >
              <span className="step-icon">
                <ShieldCheck aria-hidden="true" />
              </span>
              <div>
                <p className="step-number">04</p>
                <h2 id="preview-step">{copy.previewHeading}</h2>
              </div>
              <form onSubmit={requestPreview}>
                <label>
                  <span>{copy.dealHeading}</span>
                  <select name="dealId" required>
                    {resources.deals.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.id.slice(0, 8)} · {item.status}
                      </option>
                    ))}
                  </select>
                </label>
                <Button
                  disabled={
                    !can("documents.preview") ||
                    busy === "preview" ||
                    resources.deals.length === 0 ||
                    !resources.templateVersionId
                  }
                  type="submit"
                >
                  {busy === "preview" ? copy.working : copy.previewAction}
                </Button>
              </form>
            </section>
          </div>

          <section
            aria-labelledby="inventory-records-title"
            className="inventory-records"
          >
            <h2 id="inventory-records-title">{copy.inventoryRecentHeading}</h2>
            {resources.inventory.length === 0 ? (
              <p>{copy.inventoryEmpty}</p>
            ) : (
              <>
                <ul className="inventory-cards">
                  {resources.inventory.map((item) => (
                    <li key={item.id}>
                      <strong>{item.stockNumber}</strong>
                      <span>
                        {copy.inventoryStatusLabel}:{" "}
                        {inventoryStatusLabel(copy, item.status)}
                      </span>
                    </li>
                  ))}
                </ul>
                <div className="inventory-table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th scope="col">{copy.stockLabel}</th>
                        <th scope="col">{copy.inventoryStatusLabel}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {resources.inventory.map((item) => (
                        <tr key={item.id}>
                          <td>{item.stockNumber}</td>
                          <td>{inventoryStatusLabel(copy, item.status)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </>
            )}
          </section>

          <section aria-labelledby="recent-title" className="recent-records">
            <h2 id="recent-title">{copy.recentHeading}</h2>
            {resources.documents.length === 0 ? (
              <p>{copy.emptyRows}</p>
            ) : (
              <ul>
                {resources.documents.map((document) => (
                  <li key={document.id}>
                    <span>{document.watermark}</span>
                    <strong>
                      {document.status === "generated"
                        ? copy.statusGenerated
                        : document.status === "failed"
                          ? copy.statusFailed
                          : copy.statusQueued}
                    </strong>
                    {document.artifact ? (
                      <Button
                        disabled={busy === `open:${document.id}`}
                        onClick={() => openPreview(document)}
                        size="sm"
                        type="button"
                        variant="outline"
                      >
                        {copy.openPreviewAction}
                      </Button>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}

      <p aria-live="polite" className="operations-status" role="status">
        {status}
      </p>
    </div>
  );
}
