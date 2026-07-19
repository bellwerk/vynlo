import { expect, test, type Page, type Route } from "@playwright/test";

const workspaceA = "10000000-0000-4000-8000-0000000000a1";
const workspaceB = "10000000-0000-4000-8000-0000000000b1";
const stockDefinitionA = "20000000-0000-4000-8000-0000000000a1";
const stockDefinitionB = "20000000-0000-4000-8000-0000000000b1";
const userId = "30000000-0000-4000-8000-000000000001";
const vinRequestId = "40000000-0000-4000-8000-000000000001";
const vinResultId = "40000000-0000-4000-8000-000000000002";
const inventoryUnitId = "60000000-0000-4000-8000-0000000000a1";

function segment(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

const accessToken = `${segment({ alg: "HS256", typ: "JWT" })}.${segment({
  aal: "aal2",
  aud: "authenticated",
  email: "operator@example.invalid",
  exp: 4_102_444_800,
  role: "authenticated",
  sub: userId,
})}.${segment("inventory-workspace-safety-signature")}`;

const user = Object.freeze({
  app_metadata: { provider: "email", providers: ["email"] },
  aud: "authenticated",
  email: "operator@example.invalid",
  id: userId,
  role: "authenticated",
  user_metadata: {},
});

const session = Object.freeze({
  access_token: accessToken,
  expires_at: 4_102_444_800,
  expires_in: 3600,
  refresh_token: "inventory-workspace-safety-refresh",
  token_type: "bearer",
  user,
});

const corsHeaders = Object.freeze({
  "Access-Control-Allow-Headers":
    "authorization,apikey,content-type,x-client-info",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
});

async function json(
  route: Route,
  body: unknown,
  status = 200,
  delayMs = 0,
): Promise<void> {
  if (delayMs > 0) {
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }
  try {
    await route.fulfill({
      body: JSON.stringify(body),
      headers: corsHeaders,
      status,
    });
  } catch {
    // An AbortController may intentionally cancel a superseded workspace request.
  }
}

async function installSession(page: Page): Promise<void> {
  await page.addInitScript((storedSession) => {
    window.localStorage.setItem(
      "sb-127-auth-token",
      JSON.stringify(storedSession),
    );
  }, session);
}

function workspaceMemberships(): readonly Record<string, unknown>[] {
  return [
    {
      id: "50000000-0000-4000-8000-0000000000a1",
      workspaces: {
        default_currency: "CAD",
        id: workspaceA,
        name: "Workspace Alpha",
        odometer_unit: "km",
      },
    },
    {
      id: "50000000-0000-4000-8000-0000000000b1",
      workspaces: {
        default_currency: "USD",
        id: workspaceB,
        name: "Workspace Beta",
        odometer_unit: "mi",
      },
    },
  ];
}

async function mockSupabase(
  page: Page,
  stockDelayForWorkspaceA = 0,
): Promise<void> {
  await page.context().route("http://127.0.0.1:54321/**", async (route) => {
    const request = route.request();
    if (request.method() === "OPTIONS") {
      await route.fulfill({ headers: corsHeaders, status: 204 });
      return;
    }
    const url = new URL(request.url());
    if (url.pathname === "/auth/v1/user") {
      await json(route, user);
      return;
    }
    if (url.pathname === "/rest/v1/workspace_memberships") {
      await json(route, workspaceMemberships());
      return;
    }
    if (url.pathname === "/rest/v1/stock_number_definitions") {
      const targetWorkspaceId = url.searchParams
        .get("workspace_id")
        ?.replace(/^eq\./u, "");
      const isAlpha = targetWorkspaceId === workspaceA;
      await json(
        route,
        [
          {
            id: isAlpha ? stockDefinitionA : stockDefinitionB,
            key: isAlpha ? "alpha.default" : "beta.default",
            numeric_width: 5,
            prefix: isAlpha ? "A-" : "B-",
            version: 1,
          },
        ],
        200,
        isAlpha ? stockDelayForWorkspaceA : 0,
      );
      return;
    }
    await json(route, { message: "unexpected_supabase_request" }, 500);
  });
}

function inventoryItem(
  workspaceId: string,
  stockNumber: string,
): Record<string, unknown> {
  return {
    advertisedPriceMinor: null,
    canonicalStatus: "active",
    currencyCode: workspaceId === workspaceA ? "CAD" : "USD",
    daysInStock: 1,
    inventoryUnitId:
      workspaceId === workspaceA
        ? "60000000-0000-4000-8000-0000000000a1"
        : "60000000-0000-4000-8000-0000000000b1",
    locationId:
      workspaceId === workspaceA
        ? "70000000-0000-4000-8000-0000000000a1"
        : "70000000-0000-4000-8000-0000000000b1",
    locationName: workspaceId === workspaceA ? "Alpha lot" : "Beta lot",
    make: workspaceId === workspaceA ? "Alpha" : "Beta",
    model: "Vehicle",
    modelYear: 2026,
    stockNumber,
    trim: null,
    updatedAt: "2026-07-16T12:00:00.000Z",
    vin: workspaceId === workspaceA ? "1TEST23ABCD456789" : "2SAMP34EFGH567890",
  };
}

test("T-TEN-002 / T-TEN-003 discards delayed inventory and auxiliary responses after a workspace switch", async ({
  page,
}) => {
  await installSession(page);
  await mockSupabase(page);

  const responseDelay = 450;
  await page.route("**/api/v1/inventory-units?*", async (route) => {
    const targetWorkspaceId = route.request().headers()["x-workspace-id"];
    const isAlpha = targetWorkspaceId === workspaceA;
    await json(
      route,
      {
        data: {
          items: [
            inventoryItem(
              targetWorkspaceId ?? "",
              isAlpha ? "A-00001" : "B-00001",
            ),
          ],
        },
      },
      200,
      isAlpha ? responseDelay : 0,
    );
  });
  await page.route("**/api/v1/locations", async (route) => {
    const targetWorkspaceId = route.request().headers()["x-workspace-id"];
    const isAlpha = targetWorkspaceId === workspaceA;
    await json(
      route,
      {
        data: {
          items: [
            {
              id: isAlpha
                ? "70000000-0000-4000-8000-0000000000a1"
                : "70000000-0000-4000-8000-0000000000b1",
              name: isAlpha ? "Alpha lot" : "Beta lot",
            },
          ],
        },
      },
      200,
      isAlpha ? responseDelay : 0,
    );
  });
  await page.route("**/api/v1/inventory-saved-views", async (route) => {
    const isAlpha = route.request().headers()["x-workspace-id"] === workspaceA;
    await json(
      route,
      { data: { items: [] } },
      200,
      isAlpha ? responseDelay : 0,
    );
  });

  await page.goto("/inventory");
  const workspaceSelector = page.getByLabel("Workspace", { exact: true });
  await expect(workspaceSelector).toHaveValue(workspaceA);
  await workspaceSelector.selectOption(workspaceB);

  const visibleBetaStock = page
    .getByText("B-00001", { exact: true })
    .filter({ visible: true });
  await expect(visibleBetaStock).toBeVisible();
  const locationSelector = page.getByRole("combobox", {
    exact: true,
    name: "Location",
  });
  await expect(locationSelector).toContainText("Beta lot");
  await page.waitForTimeout(responseDelay + 150);
  await expect(visibleBetaStock).toBeVisible();
  await expect(page.getByText("A-00001", { exact: true })).toHaveCount(0);
  await expect(locationSelector).not.toContainText("Alpha lot");
});

test("T-TEN-002 / T-TEN-003 keeps delayed stock definitions and VIN polling bound to the selected workspace", async ({
  page,
}) => {
  await installSession(page);
  await mockSupabase(page, 450);
  const requestWorkspaces: string[] = [];

  await page.route("**/api/v1/vin/decode", async (route) => {
    requestWorkspaces.push(
      route.request().headers()["x-workspace-id"] ?? "missing",
    );
    await json(
      route,
      {
        data: {
          aggregateVersion: 1,
          jobStatus: "queued",
          vinDecodeRequestId: vinRequestId,
        },
      },
      202,
    );
  });
  await page.route(`**/api/v1/vin/decode/${vinRequestId}`, async (route) => {
    requestWorkspaces.push(
      route.request().headers()["x-workspace-id"] ?? "missing",
    );
    await json(route, {
      data: {
        aggregateVersion: 2,
        duplicateCandidates: [],
        duplicateReview: null,
        job: {
          attemptCount: 1,
          maximumAttempts: 5,
          retryable: false,
          reviewRequired: false,
        },
        provider: { rawResultReference: vinResultId, warnings: [] },
        status: "succeeded",
        suggestions: {
          bodyType: null,
          cylinders: null,
          drivetrain: null,
          engineLiters: null,
          fuelType: null,
          horsepower: null,
          make: "Beta",
          model: "Vehicle",
          modelYear: 2026,
          transmission: null,
          trimName: null,
        },
        vin: "1TEST23ABCD456789",
        vinDecodeRequestId: vinRequestId,
      },
    });
  });

  await page.goto("/inventory/new");
  const workspaceSelector = page.getByLabel("Workspace", { exact: true });
  await expect(workspaceSelector).toHaveValue(workspaceA);
  await workspaceSelector.selectOption(workspaceB);
  await page
    .getByRole("textbox", { name: "VIN", exact: true })
    .fill("1TEST23ABCD456789");
  await page.getByRole("button", { name: "Start VIN decode" }).click();
  await expect(page.getByText("Decode complete", { exact: true })).toBeVisible({
    timeout: 5_000,
  });
  await page.getByRole("button", { name: "Confirm vehicle details" }).click();

  await expect(page.getByLabel("Active stock definition")).toHaveValue(
    stockDefinitionB,
  );
  await expect(
    page
      .getByLabel("Active stock definition")
      .getByRole("option", { name: /alpha.default/u }),
  ).toHaveCount(0);
  expect(requestWorkspaces).toEqual([workspaceB, workspaceB]);
});

test("T-TEN-002 / T-INV-004 locks inventory operations to the command workspace until its bound reload completes", async ({
  page,
}) => {
  await installSession(page);
  await mockSupabase(page);
  const commandWorkspaces: string[] = [];
  const readWorkspaces: string[] = [];
  const detail = {
    acquisitionDate: null,
    acquiredAt: null,
    advertisedPriceMinor: "2500000",
    aggregateVersion: 1,
    allowedTransitions: [],
    availableAt: null,
    capabilities: {
      canCreateCosts: false,
      canOverrideFacts: false,
      canReadCosts: false,
      canReadInternal: false,
      canReverseCosts: false,
      canTransferLocation: false,
      canTransitionWorkflow: false,
      canUpdateDetails: true,
      canUpdateInternal: false,
      hasRecentStrongAuthentication: true,
    },
    canonicalStatus: "active",
    closedAt: null,
    conditionKey: null,
    currencyCode: "CAD",
    estimatedGrossMinor: null,
    expectedSalePriceMinor: null,
    internalNotes: null,
    inventoryUnitId,
    location: {
      id: "70000000-0000-4000-8000-0000000000a1",
      name: "Alpha lot",
    },
    odometer: null,
    postedCostMinor: null,
    publicNotes: null,
    soldAt: null,
    stockNumber: "A-00001",
    updatedAt: "2026-07-16T12:00:00.000Z",
    vehicleFacts: {
      bodyType: null,
      cylinders: null,
      drivetrain: null,
      engineLiters: null,
      factsVersion: 1,
      fuelType: null,
      horsepower: null,
      make: "Alpha",
      model: "Vehicle",
      modelYear: 2026,
      transmission: null,
      trimName: null,
      vin: "1TEST23ABCD456789",
    },
    vehicleId: "80000000-0000-4000-8000-0000000000a1",
    workflowConfigurationVersion: "1.0.0",
    workflowInstanceVersion: 1,
    workflowStateKey: "ready",
  };

  await page.route(
    `**/api/v1/inventory-units/${inventoryUnitId}`,
    async (route) => {
      const targetWorkspaceId =
        route.request().headers()["x-workspace-id"] ?? "missing";
      if (route.request().method() === "PATCH") {
        commandWorkspaces.push(targetWorkspaceId);
        await json(route, { data: { aggregateVersion: 2 } }, 200, 450);
        return;
      }
      readWorkspaces.push(targetWorkspaceId);
      await json(route, { data: detail });
    },
  );
  await page.route("**/api/v1/locations", async (route) => {
    readWorkspaces.push(
      route.request().headers()["x-workspace-id"] ?? "missing",
    );
    await json(route, {
      data: {
        items: [
          {
            id: "70000000-0000-4000-8000-0000000000a1",
            key: "alpha.lot",
            locale: "en-CA",
            name: "Alpha lot",
            timezone: "America/Toronto",
            version: 1,
          },
        ],
      },
    });
  });

  await page.goto(`/inventory/${inventoryUnitId}?workspace=${workspaceA}`);
  await expect(
    page.getByRole("heading", { level: 1, name: "2026 Alpha Vehicle" }),
  ).toBeVisible();
  const workspaceSelector = page.getByLabel("Workspace", { exact: true });
  await expect(workspaceSelector).toBeEnabled();

  await page.getByLabel("Public notes").fill("Workspace-bound update");
  await page.getByRole("button", { name: "Save details" }).click();
  await expect(workspaceSelector).toBeDisabled();
  await expect(
    page.getByRole("status").filter({ hasText: "Changes saved." }),
  ).toBeVisible();
  await expect(workspaceSelector).toBeEnabled();

  expect(commandWorkspaces).toEqual([workspaceA]);
  expect(readWorkspaces.length).toBeGreaterThanOrEqual(4);
  expect(readWorkspaces.every((workspace) => workspace === workspaceA)).toBe(
    true,
  );
});
