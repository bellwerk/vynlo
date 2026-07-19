// Stable test IDs: T-AUTH-001, T-UX-001, T-UX-002, T-I18N-001.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page, type Route } from "@playwright/test";

const workspaceId = "10000000-0000-4000-8000-000000000001";
const membershipId = "40000000-0000-4000-8000-000000000001";
const userId = "30000000-0000-4000-8000-000000000001";
const roleId = "50000000-0000-4000-8000-000000000001";
const permissionIds = [
  "60000000-0000-4000-8000-000000000001",
  "60000000-0000-4000-8000-000000000002",
  "60000000-0000-4000-8000-000000000003",
  "60000000-0000-4000-8000-000000000004",
  "60000000-0000-4000-8000-000000000005",
] as const;
const permissionKeys = [
  "users.manage",
  "inventory.create",
  "crm.create",
  "deals.create",
  "documents.preview",
] as const;

interface WorkspaceFixtureState {
  artifacts: Record<string, unknown>[];
  deals: Record<string, unknown>[];
  documents: Record<string, unknown>[];
  inventory: Record<string, unknown>[];
  parties: Record<string, unknown>[];
}

function workspaceFixtureState(
  input: Partial<WorkspaceFixtureState> = {},
): WorkspaceFixtureState {
  return {
    artifacts: input.artifacts ?? [],
    deals: input.deals ?? [],
    documents: input.documents ?? [],
    inventory: input.inventory ?? [],
    parties: input.parties ?? [],
  };
}

function segment(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function tokenForAssurance(aal: "aal1" | "aal2"): string {
  return `${segment({ alg: "HS256", typ: "JWT" })}.${segment({
    aal,
    amr:
      aal === "aal2"
        ? [{ method: "totp", timestamp: 1_784_171_200 }]
        : [{ method: "password", timestamp: 1_784_171_100 }],
    aud: "authenticated",
    email: "administrator@example.invalid",
    exp: 4_102_444_800,
    role: "authenticated",
    sub: userId,
  })}.${segment(`e2e-${aal}-signature`)}`;
}

const accessToken = tokenForAssurance("aal2");

const user = Object.freeze({
  app_metadata: { provider: "email", providers: ["email"] },
  aud: "authenticated",
  confirmed_at: "2026-07-16T12:00:00.000Z",
  created_at: "2026-07-16T12:00:00.000Z",
  email: "administrator@example.invalid",
  email_confirmed_at: "2026-07-16T12:00:00.000Z",
  factors: [],
  id: userId,
  identities: [],
  last_sign_in_at: "2026-07-16T12:00:00.000Z",
  phone: "",
  role: "authenticated",
  updated_at: "2026-07-16T12:00:00.000Z",
  user_metadata: {},
});

const corsHeaders = Object.freeze({
  "Access-Control-Allow-Headers":
    "authorization,apikey,content-type,x-client-info",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
});

async function json(route: Route, body: unknown, status = 200): Promise<void> {
  await route.fulfill({
    body: JSON.stringify(body),
    headers: corsHeaders,
    status,
  });
}

async function mockAuthenticatedWorkspace(
  page: Page,
  state: WorkspaceFixtureState,
): Promise<void> {
  await page.context().route("http://127.0.0.1:54321/**", async (route) => {
    const request = route.request();
    if (request.method() === "OPTIONS") {
      await route.fulfill({ headers: corsHeaders, status: 204 });
      return;
    }

    const url = new URL(request.url());
    if (url.pathname === "/auth/v1/token") {
      await json(route, {
        access_token: accessToken,
        expires_at: 4_102_444_800,
        expires_in: 3600,
        refresh_token: "e2e-refresh-token",
        token_type: "bearer",
        user,
      });
      return;
    }
    if (url.pathname === "/auth/v1/user") {
      await json(route, user);
      return;
    }
    if (
      request.method() === "GET" &&
      url.pathname.startsWith("/storage/v1/object/sign/document-previews/")
    ) {
      await route.fulfill({
        body: "<!doctype html><html><body><h1>DRAFT / NON-PRODUCTION</h1><p>Synthetic transaction preview</p></body></html>",
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "X-Content-Type-Options": "nosniff",
        },
        status: 200,
      });
      return;
    }

    const table = url.pathname.match(/^\/rest\/v1\/([a-z_]+)$/u)?.[1];
    const responses: Readonly<Record<string, unknown>> = {
      deals: state.deals,
      document_preview_artifacts: state.artifacts,
      document_template_versions: [
        { id: "82000000-0000-4000-8000-000000000001" },
      ],
      documents: state.documents,
      inventory_units: state.inventory,
      membership_roles: [{ role_id: roleId }],
      parties: state.parties,
      permissions: permissionKeys.map((key) => ({ key })),
      role_permissions: permissionIds.map((permission_id) => ({
        permission_id,
      })),
      roles: [{ id: roleId, name: "Workspace administrator" }],
      stock_number_definitions: [
        { id: "71000000-0000-4000-8000-000000000001" },
      ],
      workspace_memberships: [
        {
          id: membershipId,
          workspace_id: workspaceId,
          workspaces: {
            default_currency: "CAD",
            default_locale: "en-CA",
            id: workspaceId,
            name: "Synthetic North",
            odometer_unit: "km",
          },
        },
      ],
    };
    if (table && table in responses) {
      await json(route, responses[table]);
      return;
    }
    await json(route, { message: "unexpected_e2e_supabase_request" }, 500);
  });
}

async function signInAsAdministrator(page: Page): Promise<void> {
  await page.goto("/login");
  await page.getByLabel("Work email").fill("administrator@example.invalid");
  await page.getByLabel("Password (optional)").fill("synthetic-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(
    page.getByRole("heading", { name: "Authenticated operations" }),
  ).toBeVisible();
}

test("an AAL2 administrator queues an invite without browser token authority", async ({
  page,
}) => {
  await mockAuthenticatedWorkspace(
    page,
    workspaceFixtureState({
      inventory: [
        {
          id: "73000000-0000-4000-8000-000000000001",
          status: "draft",
          stock_number: "N-00001",
        },
      ],
    }),
  );
  let invitationRequest: { body: unknown; headers: Headers } | null = null;
  await page.route("**/api/v1/workspace-invitations", async (route) => {
    const request = route.request();
    invitationRequest = {
      body: request.postDataJSON(),
      headers: new Headers(request.headers()),
    };
    await json(
      route,
      {
        data: {
          invitationId: "90000000-0000-4000-8000-000000000001",
          invitationStatus: "pending",
          jobId: "90000000-0000-4000-8000-000000000002",
          jobStatus: "queued",
          outboxEventId: "90000000-0000-4000-8000-000000000003",
          replayed: false,
        },
      },
      202,
    );
  });

  await signInAsAdministrator(page);

  await expect(
    page.getByRole("heading", { name: "Invite a workspace user" }),
  ).toBeVisible();
  if ((page.viewportSize()?.width ?? 0) < 760) {
    await expect(
      page.getByRole("list").filter({ hasText: "N-00001" }),
    ).toBeVisible();
    await expect(page.getByRole("table")).toBeHidden();
  } else {
    await expect(page.getByRole("table")).toBeVisible();
    await expect(page.getByRole("cell", { name: "N-00001" })).toBeVisible();
  }
  await page
    .getByLabel("Invitee work email")
    .fill("invited.user@example.invalid");
  await page.getByLabel("Workspace administrator").check();
  await page.getByRole("button", { name: "Queue secure invitation" }).click();
  await expect(
    page.getByRole("status").filter({ hasText: /queued for secure delivery/i }),
  ).toBeVisible();

  expect(invitationRequest).not.toBeNull();
  const captured = invitationRequest!;
  expect(captured.body).toMatchObject({
    email: "invited.user@example.invalid",
    requestedLocale: "en-CA",
    roleIds: [roleId],
  });
  expect(JSON.stringify(captured.body)).not.toMatch(
    /workspaceId|token|service.role/iu,
  );
  expect(captured.headers.get("authorization")).toBe(`Bearer ${accessToken}`);
  expect(captured.headers.get("x-workspace-id")).toBe(workspaceId);

  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});

test("an invited AAL1 user reloads workspace access after MFA verification", async ({
  page,
}) => {
  const invitationId = "90000000-0000-4000-8000-000000000010";
  const factorId = "91000000-0000-4000-8000-000000000001";
  const aal1AccessToken = tokenForAssurance("aal1");
  let aal2Established = false;
  let membershipReads = 0;
  let acceptanceRequest: { body: unknown; headers: Headers } | null = null;

  await page.context().route("http://127.0.0.1:54321/**", async (route) => {
    const request = route.request();
    if (request.method() === "OPTIONS") {
      await route.fulfill({ headers: corsHeaders, status: 204 });
      return;
    }

    const url = new URL(request.url());
    const verifiedUser = {
      ...user,
      factors: [
        {
          created_at: "2026-07-16T12:00:00.000Z",
          factor_type: "totp",
          friendly_name: "Vynlo authenticator",
          id: factorId,
          status: "verified",
          updated_at: "2026-07-16T12:00:00.000Z",
        },
      ],
    };
    if (url.pathname === "/auth/v1/token") {
      await json(route, {
        access_token: aal1AccessToken,
        expires_at: 4_102_444_800,
        expires_in: 3600,
        refresh_token: "e2e-aal1-refresh-token",
        token_type: "bearer",
        user,
      });
      return;
    }
    if (url.pathname === "/auth/v1/user") {
      await json(route, aal2Established ? verifiedUser : user);
      return;
    }
    if (request.method() === "POST" && url.pathname === "/auth/v1/factors") {
      await json(route, {
        friendly_name: "Vynlo authenticator",
        id: factorId,
        totp: {
          qr_code: "%3Csvg xmlns='http://www.w3.org/2000/svg'/%3E",
          secret: "SYNTHETICMFASECRET",
          uri: "otpauth://totp/Vynlo:synthetic",
        },
        type: "totp",
      });
      return;
    }
    if (
      request.method() === "POST" &&
      url.pathname === `/auth/v1/factors/${factorId}/challenge`
    ) {
      await json(route, {
        expires_at: 4_102_444_800,
        id: "92000000-0000-4000-8000-000000000001",
        type: "totp",
      });
      return;
    }
    if (
      request.method() === "POST" &&
      url.pathname === `/auth/v1/factors/${factorId}/verify`
    ) {
      aal2Established = true;
      await json(route, {
        access_token: accessToken,
        expires_in: 3600,
        refresh_token: "e2e-aal2-refresh-token",
        token_type: "bearer",
        user: verifiedUser,
      });
      return;
    }

    const table = url.pathname.match(/^\/rest\/v1\/([a-z_]+)$/u)?.[1];
    if (table === "workspace_memberships") {
      membershipReads += 1;
      await json(
        route,
        aal2Established
          ? [
              {
                id: membershipId,
                workspace_id: workspaceId,
                workspaces: {
                  default_currency: "CAD",
                  default_locale: "en-CA",
                  id: workspaceId,
                  name: "Synthetic North",
                  odometer_unit: "km",
                },
              },
            ]
          : [],
      );
      return;
    }
    const responses: Readonly<Record<string, unknown>> = {
      deals: [],
      document_preview_artifacts: [],
      document_template_versions: [
        { id: "82000000-0000-4000-8000-000000000001" },
      ],
      documents: [],
      inventory_units: [
        {
          id: "73000000-0000-4000-8000-000000000010",
          status: "draft",
          stock_number: "N-00010",
        },
      ],
      membership_roles: [{ role_id: roleId }],
      parties: [],
      permissions: permissionKeys.map((key) => ({ key })),
      role_permissions: permissionIds.map((permission_id) => ({
        permission_id,
      })),
      roles: [{ id: roleId, name: "Workspace administrator" }],
      stock_number_definitions: [
        { id: "71000000-0000-4000-8000-000000000001" },
      ],
    };
    if (table && table in responses) {
      await json(route, responses[table]);
      return;
    }
    await json(route, { message: "unexpected_aal1_supabase_request" }, 500);
  });

  await page.route("**/api/v1/workspace-invitations/accept", async (route) => {
    const request = route.request();
    acceptanceRequest = {
      body: request.postDataJSON(),
      headers: new Headers(request.headers()),
    };
    await json(
      route,
      {
        data: {
          invitationId,
          invitationStatus: "accepted",
          membershipId,
          replayed: false,
        },
      },
      201,
    );
  });

  await page.goto(`/login?invitation=${invitationId}&workspace=${workspaceId}`);
  await page.getByLabel("Work email").fill("administrator@example.invalid");
  await page.getByLabel("Password (optional)").fill("synthetic-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(
    page.getByRole("heading", { name: "Strong authentication required" }),
  ).toBeVisible();
  expect(acceptanceRequest).not.toBeNull();
  expect(acceptanceRequest!.body).toEqual({ invitationId });
  expect(acceptanceRequest!.headers.get("x-workspace-id")).toBe(workspaceId);

  await page.getByRole("button", { name: "Set up authenticator" }).click();
  await expect(page.getByText("SYNTHETICMFASECRET")).toBeVisible();
  await page.getByLabel("Authenticator code").fill("123456");
  await page.getByRole("button", { name: "Verify secure session" }).click();

  const workspaceSelect = page.getByLabel("Workspace", { exact: true });
  await expect(workspaceSelect).toHaveValue(workspaceId);
  await expect(workspaceSelect).toContainText("Synthetic North");
  if ((page.viewportSize()?.width ?? 0) < 760) {
    await expect(
      page.getByRole("list").filter({ hasText: "N-00010" }),
    ).toBeVisible();
  } else {
    await expect(page.getByRole("cell", { name: "N-00010" })).toBeVisible();
  }
  expect(aal2Established).toBe(true);
  expect(membershipReads).toBeGreaterThanOrEqual(2);

  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});

test("T-AUTH-001 / T-UX-001 completes the M1 inventory-to-private-preview UI path", async ({
  page,
}) => {
  const state = workspaceFixtureState({
    inventory: [
      {
        id: "73000000-0000-4000-8000-000000000002",
        status: "draft",
        stock_number: "N-00042",
      },
    ],
  });
  await mockAuthenticatedWorkspace(page, state);
  const commands: Array<{
    readonly body: Record<string, unknown>;
    readonly headers: Headers;
    readonly path: string;
  }> = [];

  async function capture(route: Route, path: string) {
    const request = route.request();
    commands.push({
      body: request.postDataJSON() as Record<string, unknown>,
      headers: new Headers(request.headers()),
      path,
    });
  }

  await page.route("**/api/v1/parties", async (route) => {
    await capture(route, "party");
    state.parties = [
      {
        display_name: "Alice Example",
        id: "74000000-0000-4000-8000-000000000001",
        party_type: "person",
      },
    ];
    await json(
      route,
      {
        data: {
          partyId: "74000000-0000-4000-8000-000000000001",
          replayed: false,
        },
      },
      201,
    );
  });
  await page.route("**/api/v1/deals", async (route) => {
    await capture(route, "deal");
    state.deals = [
      {
        id: "75000000-0000-4000-8000-000000000001",
        status: "draft",
      },
    ];
    await json(
      route,
      {
        data: {
          dealId: "75000000-0000-4000-8000-000000000001",
          inventoryLinkId: "75000000-0000-4000-8000-000000000002",
          participantId: "75000000-0000-4000-8000-000000000003",
          replayed: false,
        },
      },
      201,
    );
  });
  await page.route("**/api/v1/documents/preview", async (route) => {
    await capture(route, "preview");
    const documentId = "76000000-0000-4000-8000-000000000001";
    state.documents = [
      {
        id: documentId,
        status: "queued",
        watermark: "DRAFT / NON-PRODUCTION",
      },
    ];
    await json(
      route,
      {
        data: {
          documentId,
          jobId: "76000000-0000-4000-8000-000000000002",
          jobStatus: "queued",
          outboxEventId: "76000000-0000-4000-8000-000000000003",
          previewStatus: "queued",
          replayed: false,
          watermark: "DRAFT / NON-PRODUCTION",
        },
      },
      202,
    );
    setTimeout(() => {
      state.documents = [
        {
          id: documentId,
          status: "generated",
          watermark: "DRAFT / NON-PRODUCTION",
        },
      ];
      state.artifacts = [
        {
          id: "76000000-0000-4000-8000-000000000004",
          document_id: documentId,
        },
      ];
    }, 250);
  });
  await page.route(
    "**/api/v1/document-preview-artifacts/*/download-grants",
    async (route) => {
      await capture(route, "preview-download");
      await json(route, {
        data: {
          artifactId: "76000000-0000-4000-8000-000000000004",
          auditEventId: "76000000-0000-4000-8000-000000000005",
          byteSize: 128,
          checksumSha256: "a".repeat(64),
          documentId: "76000000-0000-4000-8000-000000000001",
          download: {
            expiresAt: new Date(Date.now() + 60_000).toISOString(),
            url: `http://127.0.0.1:54321/storage/v1/object/sign/document-previews/${workspaceId}/documents/preview.html?token=e2e-signed-token`,
          },
          filename: "preview.html",
          mimeType: "text/html; charset=utf-8",
          replayed: false,
        },
      });
    },
  );

  await signInAsAdministrator(page);
  await expect(
    page.getByRole("link", { name: "Start inventory intake" }),
  ).toHaveAttribute("href", "/inventory/new");
  const currentInventory = page.getByRole("region", {
    name: "Current inventory",
  });
  if ((page.viewportSize()?.width ?? 0) < 760) {
    await expect(
      currentInventory.getByRole("listitem").filter({ hasText: "N-00042" }),
    ).toBeVisible();
  } else {
    await expect(
      currentInventory.getByRole("cell", { name: "N-00042" }),
    ).toBeVisible();
  }

  await page.getByLabel("Display name").fill("Alice Example");
  await page.getByRole("button", { name: "Create party" }).click();
  await page.getByRole("button", { name: "Create deal draft" }).click();
  await expect(
    page.getByRole("status").filter({ hasText: /Deal draft: 75000000/ }),
  ).toBeVisible();

  await page.getByRole("button", { name: "Queue watermarked preview" }).click();
  await expect(
    page
      .getByRole("status")
      .filter({ hasText: /queued for durable processing/i }),
  ).toBeVisible();
  const openPreview = page.getByRole("button", { name: "Open preview" });
  await expect(openPreview).toBeVisible({ timeout: 5_000 });

  const popupPromise = page.waitForEvent("popup");
  await openPreview.click();
  const popup = await popupPromise;
  await expect(
    popup.getByRole("heading", { name: "DRAFT / NON-PRODUCTION" }),
  ).toBeVisible();
  await popup.close();

  expect(commands.map(({ path }) => path)).toEqual([
    "party",
    "deal",
    "preview",
    "preview-download",
  ]);
  for (const command of commands) {
    expect(JSON.stringify(command.body)).not.toMatch(
      /workspaceId|service.role|token/iu,
    );
    expect(command.headers.get("authorization")).toBe(`Bearer ${accessToken}`);
    expect(command.headers.get("x-workspace-id")).toBe(workspaceId);
    expect(command.headers.get("idempotency-key")).toMatch(/^[0-9a-f-]{36}$/u);
  }
  expect(commands[1]?.body).toMatchObject({
    inventory: { roleKey: "sold" },
    participant: { roleKey: "customer.primary" },
  });

  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
