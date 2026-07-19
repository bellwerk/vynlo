import AxeBuilder from "@axe-core/playwright";
import {
  expect,
  test,
  type BrowserContext,
  type Page,
  type Route,
} from "@playwright/test";

const workspaceId = "10000000-0000-4000-8000-000000000081";
const membershipId = "40000000-0000-4000-8000-000000000081";
const userId = "30000000-0000-4000-8000-000000000081";
const roleId = "50000000-0000-4000-8000-000000000081";
const permissionId = "60000000-0000-4000-8000-000000000081";
const inventoryUnitId = "71000000-0000-4000-8000-000000000081";
const mediaId = "72000000-0000-4000-8000-000000000081";
const uploadSessionId = "73000000-0000-4000-8000-000000000081";
const verificationJobId = "74000000-0000-4000-8000-000000000081";
const retryJobId = "74000000-0000-4000-8000-000000000082";
const objectKey = `${workspaceId}/vehicle-photos/${uploadSessionId}/source.jpg`;

type VerificationStatus =
  | "completed"
  | "dead_letter"
  | "queued"
  | "rejected"
  | "retry_wait"
  | "running";

const user = Object.freeze({
  app_metadata: { provider: "email", providers: ["email"] },
  aud: "authenticated",
  confirmed_at: "2026-07-16T12:00:00.000Z",
  created_at: "2026-07-16T12:00:00.000Z",
  email: "vehicle-photo-operator@example.invalid",
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
    "authorization,apikey,content-type,x-client-info,x-supabase-api-version,x-upsert",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
});

function segment(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

const accessToken = `${segment({ alg: "HS256", typ: "JWT" })}.${segment({
  aal: "aal2",
  amr: [{ method: "totp", timestamp: 1_784_171_200 }],
  aud: "authenticated",
  email: user.email,
  exp: 4_102_444_800,
  role: "authenticated",
  sub: userId,
})}.${segment("vehicle-photo-verification-e2e-signature")}`;

async function json(route: Route, body: unknown, status = 200): Promise<void> {
  await route.fulfill({
    body: JSON.stringify(body),
    headers: corsHeaders,
    status,
  });
}

async function useLocale(
  context: BrowserContext,
  locale: "en" | "fr",
): Promise<void> {
  await context.addCookies([
    {
      name: "vynlo_locale",
      url: "http://127.0.0.1:3000",
      value: locale,
    },
  ]);
}

async function mockAuthenticatedWorkspace(page: Page): Promise<void> {
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
        expires_in: 3_600,
        refresh_token: "vehicle-photo-verification-e2e-refresh",
        token_type: "bearer",
        user,
      });
      return;
    }
    if (url.pathname === "/auth/v1/user") {
      await json(route, user);
      return;
    }
    if (url.pathname === "/auth/v1/factors") {
      await json(route, { all: [], phone: [], totp: [] });
      return;
    }
    if (url.pathname.startsWith("/storage/v1/object/media-private/")) {
      await route.fulfill({ body: "{}", headers: corsHeaders, status: 201 });
      return;
    }

    const table = url.pathname.match(/^\/rest\/v1\/([a-z_]+)$/u)?.[1];
    const responses: Readonly<Record<string, unknown>> = {
      deals: [],
      document_preview_artifacts: [],
      document_template_versions: [],
      documents: [],
      inventory_units: [],
      membership_roles: [{ role_id: roleId }],
      parties: [],
      permissions: [{ key: "media.create" }],
      role_permissions: [{ permission_id: permissionId }],
      roles: [],
      workspace_memberships: [
        {
          id: membershipId,
          workspace_id: workspaceId,
          workspaces: {
            default_currency: "CAD",
            default_locale: "en-CA",
            id: workspaceId,
            name: "Synthetic Vehicle Media Lab",
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

async function signIn(page: Page, locale: "en" | "fr"): Promise<void> {
  await page.goto("/login");
  await page.locator('input[type="email"]').fill(user.email);
  await page.locator('input[type="password"]').fill("synthetic-password");
  await page
    .getByRole("button", { name: locale === "fr" ? "Se connecter" : "Sign in" })
    .click();
  await expect(page).toHaveURL(/\/operations(?:\?.*)?$/u);
}

function statusEnvelope(status: VerificationStatus): unknown {
  const terminalFailure = status === "dead_letter" || status === "rejected";
  const attemptCount =
    status === "queued"
      ? 0
      : status === "running"
        ? 1
        : status === "retry_wait"
          ? 2
          : 6;
  return {
    data: {
      completedAt: status === "completed" ? "2026-07-16T18:30:00.000Z" : null,
      failure: terminalFailure
        ? {
            classification:
              status === "dead_letter" ? "transient" : "validation",
            code:
              status === "dead_letter"
                ? "media.storage_unavailable"
                : "media.invalid_dimensions",
          }
        : null,
      job:
        status === "rejected"
          ? null
          : {
              attemptCount,
              id: verificationJobId,
              maximumAttempts: 6,
              retryAt:
                status === "retry_wait" ? "2026-07-16T18:31:00.000Z" : null,
            },
      mediaId,
      retryable: status === "dead_letter",
      status,
      uploadSessionId,
    },
  };
}

interface UploadFixture {
  readonly getIntentKeys: () => readonly string[];
  readonly getStatusCalls: () => number;
  readonly getRetryPayload: () => unknown;
  readonly uploader: ReturnType<Page["getByRole"]>;
}

async function openUploader(
  page: Page,
  locale: "en" | "fr",
  nextStatus: () => VerificationStatus | Promise<VerificationStatus>,
  onRetry?: () => void,
): Promise<UploadFixture> {
  const intentKeys: string[] = [];
  let statusCalls = 0;
  let retryPayload: unknown;

  await page.route(
    `**/api/v1/inventory-units/${inventoryUnitId}/media`,
    async (route) => {
      expect(route.request().method()).toBe("GET");
      await json(route, {
        data: { collectionVersion: 1, inventoryUnitId, items: [] },
      });
    },
  );
  await page.route(
    `**/api/v1/inventory-units/${inventoryUnitId}/media/upload-intents`,
    async (route) => {
      expect(route.request().method()).toBe("POST");
      expect(route.request().headers()["x-workspace-id"]).toBe(workspaceId);
      expect(route.request().headers()["idempotency-key"]).toBeTruthy();
      intentKeys.push(route.request().headers()["idempotency-key"]!);
      await json(
        route,
        {
          data: {
            mediaId,
            upload: {
              bucket: "media-private",
              expiresAt: "2099-07-16T18:00:00.000Z",
              objectKey,
              requiresAuthenticatedSession: true,
            },
            uploadSessionId,
          },
        },
        201,
      );
    },
  );
  await page.route(
    `**/api/v1/media/${mediaId}/complete-upload`,
    async (route) => {
      expect(route.request().method()).toBe("POST");
      expect(route.request().postDataJSON()).toEqual({ uploadSessionId });
      await json(
        route,
        {
          data: {
            jobId: verificationJobId,
            jobStatus: "queued",
            mediaId,
            uploadSessionId,
          },
        },
        202,
      );
    },
  );
  await page.route(
    `**/api/v1/media/${mediaId}/upload-sessions/${uploadSessionId}`,
    async (route) => {
      statusCalls += 1;
      expect(route.request().method()).toBe("GET");
      expect(route.request().headers()["authorization"]).toBe(
        `Bearer ${accessToken}`,
      );
      expect(route.request().headers()["x-workspace-id"]).toBe(workspaceId);
      await json(route, statusEnvelope(await nextStatus()));
    },
  );
  await page.route(
    `**/api/v1/media/${mediaId}/upload-sessions/${uploadSessionId}/retry`,
    async (route) => {
      retryPayload = route.request().postDataJSON();
      expect(route.request().method()).toBe("POST");
      expect(route.request().headers()["idempotency-key"]).toBeTruthy();
      expect(route.request().headers()["x-workspace-id"]).toBe(workspaceId);
      onRetry?.();
      await json(
        route,
        {
          data: {
            jobId: retryJobId,
            jobStatus: "queued",
            mediaId,
            uploadSessionId,
          },
        },
        202,
      );
    },
  );

  await page.goto(
    `/inventory/${inventoryUnitId}/media?workspace=${workspaceId}`,
  );
  const uploader = page.getByRole("region", {
    name: locale === "fr" ? "Ajouter une autre photo" : "Add another photo",
  });
  await expect(uploader).toBeVisible();
  await uploader
    .getByLabel(
      locale === "fr"
        ? "Choisir une photo du véhicule"
        : "Choose a vehicle photo",
    )
    .setInputFiles({
      buffer: Buffer.from("synthetic-vynlo-verification-photo"),
      mimeType: "image/jpeg",
      name: "showroom-verification.jpg",
    });
  await expect(uploader).toHaveAttribute("data-phase", "verification_queued");
  return {
    getIntentKeys: () => intentKeys,
    getRetryPayload: () => retryPayload,
    getStatusCalls: () => statusCalls,
    uploader,
  };
}

async function expectNoOverflow(page: Page): Promise<void> {
  const overflow = await page.evaluate(() => {
    const viewportWidth = document.documentElement.clientWidth;
    if (document.documentElement.scrollWidth <= viewportWidth) return [];
    return [...document.querySelectorAll<HTMLElement>("body *")]
      .filter((element) => {
        const rect = element.getBoundingClientRect();
        return rect.right > viewportWidth + 0.5 || rect.left < -0.5;
      })
      .map((element) => ({
        className: element.className,
        right: Math.round(element.getBoundingClientRect().right),
        tagName: element.tagName,
      }))
      .slice(0, 12);
  });
  expect(overflow).toEqual([]);
}

async function expectTouchTargets(uploader: UploadFixture["uploader"]) {
  const picker = await uploader
    .locator(".vehicle-photo-upload__picker")
    .boundingBox();
  expect(Math.round(picker?.height ?? 0)).toBeGreaterThanOrEqual(44);
  for (const control of await uploader.locator("button, textarea").all()) {
    const box = await control.boundingBox();
    if (box) expect(Math.round(box.height)).toBeGreaterThanOrEqual(44);
  }
}

async function expectAccessible(page: Page): Promise<void> {
  const results = await new AxeBuilder({ page })
    .include(".vehicle-photo-upload")
    .analyze();
  expect(results.violations).toEqual([]);
}

function deferred(): Readonly<{ promise: Promise<void>; resolve: () => void }> {
  let resolve = () => undefined;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

test.beforeEach(async ({ context, page }) => {
  await useLocale(context, "en");
  await mockAuthenticatedWorkspace(page);
});

test("[M2-MEDIA-AC-027][T-MED-003][T-MED-004][T-UX-001][T-UX-002] projects queued, running, retry wait, and completed without a stale receipt", async ({
  page,
}) => {
  const gates = [deferred(), deferred(), deferred()] as const;
  const statuses = ["queued", "running", "retry_wait", "completed"] as const;
  let index = 0;
  await signIn(page, "en");
  const fixture = await openUploader(page, "en", async () => {
    const current = index;
    if (current > 0) await gates[current - 1]?.promise;
    index = Math.min(current + 1, statuses.length - 1);
    return statuses[current] ?? "completed";
  });
  const statusPanel = fixture.uploader.locator(".vehicle-photo-upload__queued");
  const receipt = fixture.uploader.locator("[data-job-status]");

  await expect(statusPanel).toHaveAttribute("data-status", "queued");
  await expect(statusPanel).toContainText("Private verification is queued.");
  await expect(receipt).toHaveAttribute("data-job-status", "queued");
  await expect(receipt).toHaveText("Queued");

  gates[0].resolve();
  await expect(statusPanel).toHaveAttribute("data-status", "running");
  await expect(statusPanel).toContainText("Private verification is running.");
  await expect(receipt).toHaveAttribute("data-job-status", "running");
  await expect(receipt).toHaveText("Verification in progress");

  gates[1].resolve();
  await expect(statusPanel).toHaveAttribute("data-status", "retry_wait");
  await expect(statusPanel).toContainText(
    "Verification will retry automatically.",
  );
  await expect(receipt).toHaveAttribute("data-job-status", "retry_wait");
  await expect(receipt).toHaveText("Waiting to retry");

  gates[2].resolve();
  await expect(statusPanel).toHaveAttribute("data-status", "completed");
  await expect(statusPanel).toContainText(
    "Photo verified and queued for processing.",
  );
  await expect(receipt).toHaveAttribute("data-job-status", "succeeded");
  await expect(receipt).toHaveText("Verified");
  await expect(
    fixture.uploader.locator(".vehicle-photo-upload__stages li").nth(2),
  ).toHaveAttribute("data-state", "complete");

  await expectNoOverflow(page);
  await expectTouchTargets(fixture.uploader);
  await expectAccessible(page);
  expect(fixture.getStatusCalls()).toBe(4);
});

test("[M2-MEDIA-AC-027][T-MED-003][T-UX-001][T-UX-002] dead-letter retry requires a reason and never exposes raw failures", async ({
  page,
}) => {
  let retried = false;
  await signIn(page, "en");
  const fixture = await openUploader(
    page,
    "en",
    () => (retried ? "queued" : "dead_letter"),
    () => {
      retried = true;
    },
  );
  const statusPanel = fixture.uploader.locator(".vehicle-photo-upload__queued");
  const receipt = fixture.uploader.locator("[data-job-status]");
  await expect(statusPanel).toHaveAttribute("data-status", "dead_letter");
  await expect(statusPanel).toContainText(
    "Verification stopped after its retry limit. Review it before retrying.",
  );
  await expect(receipt).toHaveAttribute("data-job-status", "dead_letter");
  await expect(receipt).toHaveText("Verification failed");
  await expect(page.locator("body")).not.toContainText(
    "media.storage_unavailable",
  );
  await expect(page.locator("body")).not.toContainText("transient");

  const reason = fixture.uploader.getByLabel("Reason for retry");
  const retry = fixture.uploader.getByRole("button", {
    name: "Retry verification",
  });
  await retry.focus();
  await page.keyboard.press("Enter");
  await expect(
    fixture.uploader.getByText("Enter a reason before retrying verification.", {
      exact: true,
    }),
  ).toBeVisible();
  await expect(reason).toBeFocused();
  await page.keyboard.type("Storage dependency recovered");
  await page.keyboard.press("Tab");
  await expect(retry).toBeFocused();
  await page.keyboard.press("Enter");

  await expect(statusPanel).toHaveAttribute("data-status", "queued");
  await expect(statusPanel).toContainText("Private verification is queued.");
  await expect(receipt).toHaveAttribute("data-job-status", "queued");
  await expect(receipt).toHaveText("Queued");
  expect(fixture.getRetryPayload()).toEqual({
    reason: "Storage dependency recovered",
  });

  await expectNoOverflow(page);
  await expectTouchTargets(fixture.uploader);
  await expectAccessible(page);
});

test("[M2-MEDIA-AC-027][T-I18N-001][T-UX-001][T-UX-002] rejects safely in French and resets for a keyboard-driven new upload", async ({
  context,
  page,
}) => {
  await useLocale(context, "fr");
  await signIn(page, "fr");
  const fixture = await openUploader(page, "fr", () => "rejected");
  const statusPanel = fixture.uploader.locator(".vehicle-photo-upload__queued");
  const receipt = fixture.uploader.locator("[data-job-status]");

  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  await expect(statusPanel).toHaveAttribute("data-status", "rejected");
  await expect(statusPanel).toContainText(
    "Cette photo a été rejetée. Choisissez le bon fichier et commencez un nouveau téléversement.",
  );
  await expect(receipt).toHaveAttribute("data-job-status", "cancelled");
  await expect(receipt).toHaveText("Annulée");
  await expect(page.locator("body")).not.toContainText(
    "media.invalid_dimensions",
  );
  await expect(page.locator("body")).not.toContainText("validation");
  await expect(
    fixture.uploader.getByRole("button", {
      name: "Relancer la vérification",
    }),
  ).toHaveCount(0);

  await expectNoOverflow(page);
  await expectTouchTargets(fixture.uploader);
  await expectAccessible(page);

  const startNew = fixture.uploader.getByRole("button", {
    name: "Commencer un nouveau téléversement",
  });
  await startNew.focus();
  await page.keyboard.press("Enter");
  await expect(fixture.uploader).toHaveAttribute("data-phase", "idle");
  await expect(fixture.uploader).not.toHaveAttribute(
    "data-verification-status",
  );
  await expect(
    fixture.uploader.locator(".vehicle-photo-upload__visual"),
  ).toHaveAttribute("data-selected", "false");
  await expect(
    fixture.uploader.getByLabel("Choisir une photo du véhicule"),
  ).toBeFocused();
  await expectNoOverflow(page);
  await expectAccessible(page);

  await fixture.uploader
    .getByLabel("Choisir une photo du véhicule")
    .setInputFiles({
      buffer: Buffer.from("synthetic-vynlo-verification-photo"),
      mimeType: "image/jpeg",
      name: "showroom-verification.jpg",
    });
  await expect
    .poll(() => fixture.getIntentKeys().length, { timeout: 5_000 })
    .toBe(2);
  expect(fixture.getIntentKeys()[1]).not.toBe(fixture.getIntentKeys()[0]);
});
