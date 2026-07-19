import AxeBuilder from "@axe-core/playwright";
import {
  expect,
  test,
  type BrowserContext,
  type Page,
  type Route,
} from "@playwright/test";

const workspaceId = "10000000-0000-4000-8000-000000000071";
const membershipId = "40000000-0000-4000-8000-000000000071";
const userId = "30000000-0000-4000-8000-000000000071";
const roleId = "50000000-0000-4000-8000-000000000071";
const documentId = "76000000-0000-4000-8000-000000000071";
const uploadSessionId = "77000000-0000-4000-8000-000000000071";
const verificationJobId = "78000000-0000-4000-8000-000000000071";
const retryVerificationJobId = "78000000-0000-4000-8000-000000000072";
const objectKey = `${workspaceId}/legal-originals/${uploadSessionId}/source.pdf`;
const legalOriginalBytes = Buffer.from(
  "%PDF-1.7\nsynthetic legal original\n%%EOF",
);
const permissionIds = [
  "60000000-0000-4000-8000-000000000071",
  "60000000-0000-4000-8000-000000000072",
] as const;
const permissionKeys = ["media.create", "documents.upload_signed"] as const;

const user = Object.freeze({
  app_metadata: { provider: "email", providers: ["email"] },
  aud: "authenticated",
  confirmed_at: "2026-07-16T12:00:00.000Z",
  created_at: "2026-07-16T12:00:00.000Z",
  email: "media-operator@example.invalid",
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
})}.${segment("legal-original-e2e-signature")}`;

async function json(route: Route, body: unknown, status = 200): Promise<void> {
  await route.fulfill({
    body: JSON.stringify(body),
    headers: corsHeaders,
    status,
  });
}

async function mockAuthenticatedOperations(page: Page): Promise<void> {
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
        refresh_token: "legal-original-e2e-refresh",
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

    const table = url.pathname.match(/^\/rest\/v1\/([a-z_]+)$/u)?.[1];
    const responses: Readonly<Record<string, unknown>> = {
      deals: [],
      document_preview_artifacts: [],
      document_template_versions: [],
      documents: [
        {
          id: documentId,
          status: "generated",
          watermark: "DRAFT / SYNTHETIC",
        },
      ],
      inventory_units: [],
      membership_roles: [{ role_id: roleId }],
      parties: [],
      permissions: permissionKeys.map((key) => ({ key })),
      role_permissions: permissionIds.map((permission_id) => ({
        permission_id,
      })),
      roles: [],
      workspace_memberships: [
        {
          id: membershipId,
          workspace_id: workspaceId,
          workspaces: {
            default_currency: "CAD",
            default_locale: "en-CA",
            id: workspaceId,
            name: "Synthetic Media Lab",
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

async function signIn(page: Page, locale: "en" | "fr" = "en"): Promise<void> {
  await page.goto("/login");
  await page.locator('input[type="email"]').fill(user.email);
  await page.locator('input[type="password"]').fill("synthetic-password");
  await page
    .getByRole("button", { name: locale === "fr" ? "Se connecter" : "Sign in" })
    .click();
  await expect(
    page.getByRole("heading", {
      name:
        locale === "fr"
          ? "Opérations authentifiées"
          : "Authenticated operations",
    }),
  ).toBeVisible();
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

function deferred(): Readonly<{
  promise: Promise<void>;
  resolve: () => void;
}> {
  let resolve = () => undefined;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

async function expectNoOverflow(page: Page): Promise<void> {
  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);
}

async function mockSuccessfulLegalOriginalUpload(
  page: Page,
  jobStatus: "cancelled" | "queued" = "queued",
): Promise<void> {
  await page.route(
    `**/api/v1/documents/${documentId}/original-upload-intents`,
    async (route) => {
      await json(
        route,
        {
          data: {
            documentId,
            expiresAt: new Date(Date.now() + 60_000).toISOString(),
            mediaKind: "legal_document",
            upload: { bucket: "media-private", objectKey },
            uploadSessionId,
          },
        },
        201,
      );
    },
  );
  await page.route(
    `**/api/v1/documents/${documentId}/original-upload-completions`,
    async (route) => {
      await json(
        route,
        {
          data: {
            documentId,
            job: { id: verificationJobId, status: jobStatus },
            uploadSessionId,
          },
        },
        202,
      );
    },
  );
  await page.route(
    "http://127.0.0.1:54321/storage/v1/object/media-private/**",
    async (route) => {
      if (route.request().method() === "OPTIONS") {
        await route.fulfill({ headers: corsHeaders, status: 204 });
        return;
      }
      await route.fulfill({ body: "{}", headers: corsHeaders, status: 201 });
    },
  );
}

async function chooseAndUploadOriginal(
  page: Page,
  locale: "en" | "fr" = "en",
): Promise<void> {
  const uploader = page.getByRole("region", {
    name:
      locale === "fr"
        ? "Originaux légaux et signés"
        : "Legal and signed originals",
  });
  await uploader
    .getByLabel(locale === "fr" ? "PDF ou image source" : "PDF or source image")
    .setInputFiles({
      buffer: legalOriginalBytes,
      mimeType: "application/pdf",
      name: "synthetic-original.pdf",
    });
  await uploader
    .getByRole("button", {
      name: locale === "fr" ? "Téléverser l’original" : "Upload original",
    })
    .click();
  await expect(uploader).toHaveAttribute("data-phase", "queued");
}

test("[M2-MEDIA-AC-023][T-MED-002][T-MED-003][T-UX-001][T-UX-002] preserves a legal original with progress, retry, and a durable queued receipt", async ({
  page,
}) => {
  await mockAuthenticatedOperations(page);

  const commands: Array<{
    readonly body: Record<string, unknown>;
    readonly headers: Record<string, string>;
    readonly kind: "completion" | "intent";
  }> = [];
  await page.route(
    `**/api/v1/documents/${documentId}/original-upload-intents`,
    async (route) => {
      const request = route.request();
      commands.push({
        body: request.postDataJSON() as Record<string, unknown>,
        headers: request.headers(),
        kind: "intent",
      });
      await json(
        route,
        {
          data: {
            documentId,
            expiresAt: new Date(Date.now() + 60_000).toISOString(),
            mediaKind: "legal_document",
            upload: { bucket: "media-private", objectKey },
            uploadSessionId,
          },
        },
        201,
      );
    },
  );
  await page.route(
    `**/api/v1/documents/${documentId}/original-upload-completions`,
    async (route) => {
      const request = route.request();
      commands.push({
        body: request.postDataJSON() as Record<string, unknown>,
        headers: request.headers(),
        kind: "completion",
      });
      await json(
        route,
        {
          data: {
            documentId,
            job: { id: verificationJobId, status: "queued" },
            uploadSessionId,
          },
        },
        202,
      );
    },
  );
  const queuedStatusMethods: string[] = [];
  await page.route(
    `**/api/v1/documents/${documentId}/original-upload-sessions/${uploadSessionId}`,
    async (route) => {
      queuedStatusMethods.push(route.request().method());
      await json(route, {
        data: {
          completedAt: null,
          documentId,
          failure: null,
          job: {
            attemptCount: 0,
            id: verificationJobId,
            maximumAttempts: 3,
            retryAt: null,
          },
          mediaKind: "legal_document",
          retryable: false,
          status: "queued",
          uploadSessionId,
        },
      });
    },
  );

  const retryUploadStarted = deferred();
  const releaseRetryUpload = deferred();
  const storageRequests: Array<Record<string, string>> = [];
  let uploadAttempts = 0;
  await page.route(
    "http://127.0.0.1:54321/storage/v1/object/media-private/**",
    async (route) => {
      const request = route.request();
      if (request.method() === "OPTIONS") {
        await route.fulfill({ headers: corsHeaders, status: 204 });
        return;
      }
      uploadAttempts += 1;
      storageRequests.push(request.headers());
      if (uploadAttempts === 1) {
        await route.fulfill({
          body: JSON.stringify({ message: "synthetic_upload_interruption" }),
          headers: corsHeaders,
          status: 503,
        });
        return;
      }
      retryUploadStarted.resolve();
      await releaseRetryUpload.promise;
      await route.fulfill({ body: "{}", headers: corsHeaders, status: 201 });
    },
  );

  await signIn(page);
  const uploader = page.getByRole("region", {
    name: "Legal and signed originals",
  });
  await expect(uploader).toBeVisible();

  const documentSelect = uploader.getByLabel("Document");
  const legalKind = uploader.getByLabel("Legal original");
  const signedKind = uploader.getByLabel("Signed original");
  const fileInput = uploader.getByLabel("PDF or source image");
  await expect(documentSelect).toHaveValue(documentId);
  const originalTypeGroup = uploader.getByRole("group", {
    name: "Original type",
  });
  await expect(originalTypeGroup).toBeVisible();
  await originalTypeGroup.evaluate((element) => {
    element.dataset.keyboardSelectionClicks = "0";
    element.addEventListener("click", (event) => {
      if (!(event.target as Element).closest('[role="radio"]')) {
        return;
      }
      element.dataset.keyboardSelectionClicks = String(
        Number(element.dataset.keyboardSelectionClicks) + 1,
      );
    });
  });
  await documentSelect.focus();
  await page.keyboard.press("Tab");
  await expect(legalKind).toBeFocused();
  await page.keyboard.press("ArrowRight");
  await expect(signedKind).toBeChecked();
  await expect(originalTypeGroup).toHaveAttribute(
    "data-keyboard-selection-clicks",
    "1",
  );
  await expect(
    uploader.getByText(
      /strong authentication verified within the last 15 minutes/u,
    ),
  ).toBeVisible();
  await page.keyboard.press("ArrowLeft");
  await expect(legalKind).toBeChecked();
  await expect(originalTypeGroup).toHaveAttribute(
    "data-keyboard-selection-clicks",
    "2",
  );

  // A held key emits repeated keydown events before keyup. Each move must
  // select exactly once, even while Radix's document-level arrow flag is set.
  await page.keyboard.down("ArrowRight");
  await expect(signedKind).toBeChecked();
  await page.keyboard.down("ArrowRight");
  await page.keyboard.up("ArrowRight");
  await expect(legalKind).toBeChecked();
  await expect(originalTypeGroup).toHaveAttribute(
    "data-keyboard-selection-clicks",
    "4",
  );

  await fileInput.setInputFiles({
    buffer: legalOriginalBytes,
    mimeType: "application/pdf",
    name: "synthetic-original.pdf",
  });
  await uploader.getByRole("button", { name: "Upload original" }).click();

  const uploadError = uploader.getByRole("alert");
  await expect(uploadError).toContainText(
    "The upload was interrupted or refused",
  );
  const retry = uploadError.getByRole("button", { name: "Retry upload" });
  await expect(retry).toBeVisible();
  await retry.click();

  await retryUploadStarted.promise;
  const progress = uploader.getByRole("progressbar", {
    name: "Legal original upload progress",
  });
  await expect(progress).toBeVisible();
  await expect(progress).toHaveAttribute("max", "100");
  releaseRetryUpload.resolve();

  await expect(uploader).toHaveAttribute("data-phase", "queued");
  await expect.poll(() => queuedStatusMethods.length).toBeGreaterThan(0);
  expect(new Set(queuedStatusMethods)).toEqual(new Set(["GET"]));
  const queuedStatus = uploader.locator(
    '.legal-original-upload__queued[data-status="queued"]',
  );
  await expect(queuedStatus).toBeVisible();
  await expect(queuedStatus.locator("strong")).toHaveText(
    "Private verification is queued.",
  );
  await expect(uploader.locator(".legal-original-upload__live")).toHaveText(
    "Private verification is queued.",
  );
  await expect(
    uploader.locator(".legal-original-upload__receipt"),
  ).toContainText(verificationJobId.slice(0, 8));
  const stages = uploader.locator(".legal-original-upload__stages li");
  await expect(stages).toHaveCount(3);
  await expect(stages.nth(0)).toHaveAttribute("data-state", "complete");
  await expect(stages.nth(1)).toHaveAttribute("data-state", "complete");
  await expect(stages.nth(2)).toHaveAttribute("data-state", "current");

  expect(uploadAttempts).toBe(2);
  expect(commands.map(({ kind }) => kind)).toEqual(["intent", "completion"]);
  expect(commands[0]?.body).toMatchObject({
    byteSize: legalOriginalBytes.length,
    filename: "synthetic-original.pdf",
    mediaKind: "legal_document",
    mimeType: "application/pdf",
  });
  expect(commands[0]?.body.checksumSha256).toMatch(/^[0-9a-f]{64}$/u);
  expect(commands[1]?.body).toEqual({ uploadSessionId });
  for (const command of commands) {
    expect(command.headers.authorization).toBe(`Bearer ${accessToken}`);
    expect(command.headers["x-workspace-id"]).toBe(workspaceId);
    expect(command.headers["idempotency-key"]).toMatch(/^[0-9a-f-]{36}$/u);
    expect(JSON.stringify(command.body)).not.toMatch(/workspaceId|token/iu);
  }
  for (const headers of storageRequests) {
    expect(headers.authorization).toBe(`Bearer ${accessToken}`);
    expect(headers["x-upsert"]).toBe("false");
  }

  await expectNoOverflow(page);
  expect(
    await uploader.evaluate(
      (element) => element.scrollWidth > element.clientWidth,
    ),
  ).toBe(false);
  for (const control of await uploader
    .locator(
      'select, input[type="file"], button, .legal-original-upload__kinds label',
    )
    .all()) {
    const box = await control.boundingBox();
    if (box) expect(Math.round(box.height)).toBeGreaterThanOrEqual(44);
  }
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});

test("[M2-MEDIA-AC-026][T-MED-003][T-JOB-002][T-UX-001] exposes a safe dead-letter state and reasoned verification retry", async ({
  page,
}) => {
  await mockAuthenticatedOperations(page);
  await mockSuccessfulLegalOriginalUpload(page);

  let retried = false;
  let retryCommand:
    | Readonly<{
        body: Record<string, unknown>;
        headers: Record<string, string>;
        method: string;
      }>
    | undefined;
  await page.route(
    `**/api/v1/documents/${documentId}/original-upload-sessions/${uploadSessionId}`,
    async (route) => {
      await json(route, {
        data: {
          completedAt: null,
          documentId,
          failure: retried
            ? null
            : {
                classification: "transient",
                code: "media.provider_unavailable",
              },
          job: {
            attemptCount: retried ? 0 : 3,
            id: retried ? retryVerificationJobId : verificationJobId,
            maximumAttempts: 3,
            retryAt: null,
          },
          mediaKind: "legal_document",
          retryable: !retried,
          status: retried ? "queued" : "dead_letter",
          uploadSessionId,
        },
      });
    },
  );
  await page.route(
    `**/api/v1/documents/${documentId}/original-upload-sessions/${uploadSessionId}/retry`,
    async (route) => {
      const request = route.request();
      retryCommand = {
        body: request.postDataJSON() as Record<string, unknown>,
        headers: request.headers(),
        method: request.method(),
      };
      retried = true;
      await json(
        route,
        {
          data: {
            documentId,
            job: { id: retryVerificationJobId, status: "queued" },
            uploadSessionId,
          },
        },
        202,
      );
    },
  );

  await signIn(page);
  await chooseAndUploadOriginal(page);
  const uploader = page.getByRole("region", {
    name: "Legal and signed originals",
  });
  const deadLetterStatus = uploader.locator(
    '.legal-original-upload__queued[data-status="dead_letter"]',
  );
  await expect(deadLetterStatus).toBeVisible();
  await expect(deadLetterStatus.locator("strong")).toHaveText(
    "Verification stopped after its retry limit. Review it before retrying.",
  );
  await expect(uploader.locator(".legal-original-upload__live")).toHaveText(
    "Verification stopped after its retry limit. Review it before retrying.",
  );
  await expect(uploader).not.toContainText("media.provider_unavailable");
  await expect(uploader).not.toContainText("transient");

  const reason = uploader.getByLabel("Reason for retry");
  await expectNoOverflow(page);
  for (const control of await uploader.locator("textarea, button").all()) {
    const box = await control.boundingBox();
    if (box) expect(Math.round(box.height)).toBeGreaterThanOrEqual(44);
  }
  const deadLetterAxeResults = await new AxeBuilder({ page }).analyze();
  expect(deadLetterAxeResults.violations).toEqual([]);

  await reason.focus();
  await expect(reason).toBeFocused();
  await reason.fill("Provider incident reviewed by operations");
  await uploader.getByRole("button", { name: "Retry verification" }).click();

  const retriedStatus = uploader.locator(
    '.legal-original-upload__queued[data-status="queued"]',
  );
  await expect(retriedStatus).toBeVisible();
  await expect(retriedStatus.locator("strong")).toHaveText(
    "Private verification is queued.",
  );
  expect(retryCommand?.body).toEqual({
    reason: "Provider incident reviewed by operations",
  });
  expect(retryCommand?.method).toBe("POST");
  expect(retryCommand?.headers.authorization).toBe(`Bearer ${accessToken}`);
  expect(retryCommand?.headers["x-workspace-id"]).toBe(workspaceId);
  expect(retryCommand?.headers["idempotency-key"]).toMatch(/^[0-9a-f-]{36}$/u);
  await expectNoOverflow(page);
  for (const control of await uploader.locator("textarea, button").all()) {
    const box = await control.boundingBox();
    if (box) expect(Math.round(box.height)).toBeGreaterThanOrEqual(44);
  }
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});

test("[M2-MEDIA-AC-026][T-MED-003][T-I18N-001][T-UX-002] keeps rejection terminal and translated", async ({
  context,
  page,
}) => {
  await useLocale(context, "fr");
  await mockAuthenticatedOperations(page);
  await mockSuccessfulLegalOriginalUpload(page, "cancelled");
  await page.route(
    `**/api/v1/documents/${documentId}/original-upload-sessions/${uploadSessionId}`,
    async (route) => {
      await json(route, {
        data: {
          completedAt: null,
          documentId,
          failure: {
            classification: "validation",
            code: "media.signature_invalid",
          },
          job: null,
          mediaKind: "legal_document",
          retryable: false,
          status: "rejected",
          uploadSessionId,
        },
      });
    },
  );

  await signIn(page, "fr");
  await chooseAndUploadOriginal(page, "fr");
  const uploader = page.getByRole("region", {
    name: "Originaux légaux et signés",
  });
  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  const rejectedStatus = uploader.locator(
    '.legal-original-upload__queued[data-status="rejected"]',
  );
  await expect(rejectedStatus).toBeVisible();
  await expect(rejectedStatus.locator("strong")).toHaveText(
    "Cet original a été rejeté. Choisissez le bon fichier et commencez un nouveau téléversement.",
  );
  await expect(uploader.locator(".legal-original-upload__live")).toHaveText(
    "Cet original a été rejeté. Choisissez le bon fichier et commencez un nouveau téléversement.",
  );
  await expect(uploader).not.toContainText("media.signature_invalid");
  await expect(uploader).not.toContainText("validation");
  await expect(
    uploader.getByRole("button", {
      name: "Relancer la vérification",
    }),
  ).toHaveCount(0);

  const startNewUpload = uploader.getByRole("button", {
    name: "Commencer un nouveau téléversement",
  });
  const startNewUploadBox = await startNewUpload.boundingBox();
  expect(startNewUploadBox).not.toBeNull();
  expect(Math.round(startNewUploadBox?.height ?? 0)).toBeGreaterThanOrEqual(44);
  await expectNoOverflow(page);
  const rejectedAxeResults = await new AxeBuilder({ page }).analyze();
  expect(rejectedAxeResults.violations).toEqual([]);

  await startNewUpload.click();
  await expect(uploader).toHaveAttribute("data-phase", "idle");
  await expect(
    uploader.getByRole("button", { name: "Téléverser l’original" }),
  ).toBeDisabled();
  await expectNoOverflow(page);
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});

test("[M2-MEDIA-AC-022][M2-MEDIA-AC-023][T-AUTH-002][T-I18N-001][T-UX-001] keeps legal-original controls and step-up guidance usable in French", async ({
  context,
  page,
}) => {
  await useLocale(context, "fr");
  await mockAuthenticatedOperations(page);
  await signIn(page, "fr");

  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  const uploader = page.getByRole("region", {
    name: "Originaux légaux et signés",
  });
  await expect(uploader).toBeVisible();
  await expect(uploader.getByLabel("Document")).toHaveValue(documentId);
  await expect(
    uploader.getByRole("group", { name: "Type d’original" }),
  ).toBeVisible();
  await expect(uploader.getByLabel("Original légal")).toBeChecked();
  await expect(uploader.getByLabel("PDF ou image source")).toBeEnabled();
  await expect(
    uploader.getByRole("button", { name: "Téléverser l’original" }),
  ).toBeDisabled();
  await expect(
    uploader.getByRole("list", {
      name: "État du téléversement de l’original",
    }),
  ).toContainText("Empreinte");
  await uploader.getByLabel("Original signé").check();
  await expect(
    uploader.getByText(
      /authentification forte vérifiée dans les 15 dernières minutes/u,
    ),
  ).toBeVisible();
  await expect(
    uploader.getByText(/L’original n’est jamais transformé/u),
  ).toBeVisible();

  await expectNoOverflow(page);
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
