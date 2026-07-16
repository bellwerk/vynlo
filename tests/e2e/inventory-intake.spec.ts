import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

const intakePreviewPath = "/inventory/new?preview=inventory";

async function createPreviewInventory(page: Page): Promise<void> {
  await page.goto(intakePreviewPath);
  await page
    .getByRole("textbox", { name: "VIN", exact: true })
    .fill("1test23abcd456789");
  await page.getByRole("button", { name: "Start VIN decode" }).click();
  await expect(page.getByText("Decode complete", { exact: true })).toBeVisible({
    timeout: 15_000,
  });
  await page.getByRole("button", { name: "Confirm vehicle details" }).click();
  await page
    .getByRole("button", { name: "Allocate stock and add inventory" })
    .click();
  await expect(
    page.getByRole("heading", { level: 2, name: "Inventory added" }),
  ).toBeVisible();
}

test("[M2-INV-AC-001][M2-INV-AC-005][T-INV-002][T-NUM-001][T-UX-001][T-UX-002] enters inventory through a confirmed VIN workflow without page overflow", async ({
  page,
}) => {
  await page.goto("/inventory?preview=inventory");
  await page.getByRole("link", { name: "Add inventory" }).click();
  await expect(page).toHaveURL(/\/inventory\/new\?preview=inventory$/u);

  await expect(
    page.getByRole("heading", { level: 1, name: "Add inventory" }),
  ).toBeVisible();
  await expect(page.getByText("Step 1 of 3")).toBeVisible();
  await expect(
    page.getByText(/camera scanning is not supported/i),
  ).toBeVisible();

  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);

  for (const control of await page
    .locator("main input, main select, main textarea, main button, main a")
    .all()) {
    const box = await control.boundingBox();
    if (box) expect(box.height).toBeGreaterThanOrEqual(44);
  }

  await page
    .getByRole("textbox", { name: "VIN", exact: true })
    .fill("1test23abcd456789");
  await page.getByRole("button", { name: "Start VIN decode" }).click();
  await expect(
    page.getByText("Decode complete", { exact: true }),
  ).toBeVisible();
  await expect(page.getByLabel("Make")).toHaveValue("Volvo");
  await expect(
    page.getByRole("textbox", { name: "Model", exact: true }),
  ).toHaveValue("XC60");
  await expect(page.getByLabel("Trim")).toHaveValue("Plus");
  await expect(page.getByLabel("Body type")).toHaveValue(
    "Sport utility vehicle",
  );
  await expect(page.getByLabel("Cylinders")).toHaveValue("4");
  await expect(page.getByLabel("Horsepower")).toHaveValue("247");

  await page
    .getByRole("textbox", { name: "Model", exact: true })
    .fill("XC60 Recharge");
  await page.getByLabel("Cylinders").fill("6");
  await page.getByLabel("Horsepower").fill("455");
  await page.getByRole("button", { name: "Confirm vehicle details" }).click();
  await expect(page.getByText("Step 3 of 3")).toBeVisible();
  await expect(
    page.getByRole("heading", { level: 2, name: "Inventory details" }),
  ).toBeVisible();
  await expect(page.getByLabel("Active stock definition")).toHaveValue(
    "00000000-0000-4000-8000-000000000302",
  );
  await expect(page.getByLabel("Inventory location")).toHaveValue(
    "00000000-0000-4000-8000-000000000306",
  );
  await expect(page.getByLabel("Vehicle condition")).toHaveValue("used.ready");

  await page.getByLabel(/Odometer/).fill("32000");
  await page.getByLabel("Advertised price (optional)").fill("54995.09");
  await page
    .getByRole("button", { name: "Allocate stock and add inventory" })
    .click();

  await expect(
    page.getByRole("heading", { level: 2, name: "Inventory added" }),
  ).toBeVisible();
  await expect(page.getByText(/Stock SYN-00991 is ready/)).toBeVisible();
  await expect(
    page.getByRole("heading", { level: 2, name: "Add vehicle photos" }),
  ).toBeVisible();

  const photoInput = page.getByLabel("Choose a vehicle photo");
  await expect(photoInput).toHaveAttribute(
    "accept",
    /image\/jpeg.*image\/heif/u,
  );
  await photoInput.setInputFiles({
    buffer: Buffer.from("synthetic-vynlo-vehicle-photo"),
    mimeType: "image/jpeg",
    name: "vehicle-front.jpg",
  });
  await expect(page.locator(".vehicle-photo-upload")).toHaveAttribute(
    "data-phase",
    "verification_queued",
  );
  await expect(page.getByText("Hash ready", { exact: true })).toBeVisible();
  await expect(
    page.getByText("Private upload complete", { exact: true }),
  ).toBeVisible();
  await expect(page.getByText("Verification queued").first()).toBeVisible();
  await expect(page.getByText(/^[a-f0-9]{64}$/u)).toBeVisible();
  const pickerBox = await page
    .locator(".vehicle-photo-upload__picker")
    .boundingBox();
  expect(pickerBox?.height).toBeGreaterThanOrEqual(44);

  const uploadOverflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(uploadOverflow).toBe(false);
  const uploadResults = await new AxeBuilder({ page }).analyze();
  expect(uploadResults.violations).toEqual([]);
});

test("[T-UX-001][T-UX-002] validates a photo and safely retries an interrupted private upload", async ({
  page,
}) => {
  await createPreviewInventory(page);

  const uploader = page.getByRole("region", { name: "Add vehicle photos" });
  const photoInput = page.getByLabel("Choose a vehicle photo");
  await photoInput.setInputFiles({
    buffer: Buffer.from("not-an-image"),
    mimeType: "text/plain",
    name: "vehicle.txt",
  });
  await expect(uploader.getByRole("alert")).toContainText(
    "Choose a JPEG, PNG, WebP, HEIC or HEIF photo.",
  );
  await expect(page.getByRole("button", { name: "Retry safely" })).toHaveCount(
    0,
  );

  await page.getByLabel("Choose another photo").setInputFiles({
    buffer: Buffer.from("synthetic-retry-photo"),
    mimeType: "image/jpeg",
    name: "retry-photo.jpg",
  });
  await expect(
    page.getByRole("button", { name: "Retry safely" }),
  ).toBeVisible();
  await expect(uploader.getByRole("alert")).toContainText("same upload intent");
  await page.getByRole("button", { name: "Retry safely" }).click();
  await expect(page.locator(".vehicle-photo-upload")).toHaveAttribute(
    "data-phase",
    "verification_queued",
  );
  await expect(
    page.getByText("Private upload complete", { exact: true }),
  ).toBeVisible();

  const retryResults = await new AxeBuilder({ page }).analyze();
  expect(retryResults.violations).toEqual([]);
});

test("[M2-INV-AC-003][T-INV-003][T-UX-001][T-UX-002] requires review then links an open duplicate without another stock allocation", async ({
  page,
}) => {
  await page.goto(intakePreviewPath);
  await page
    .getByRole("textbox", { name: "VIN", exact: true })
    .fill("2SAMP34EFGH567890");
  await page.getByRole("button", { name: "Start VIN decode" }).click();

  await expect(
    page.getByRole("heading", { name: "Duplicate VIN review required" }),
  ).toBeVisible();
  await expect(page.getByText("Stock SYN-00120 · Active")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Confirm vehicle details" }),
  ).toBeDisabled();
  await expect(
    page.getByRole("button", { name: "Allocate stock and add inventory" }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Record duplicate review" }),
  ).toBeDisabled();
  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);
  const duplicateResults = await new AxeBuilder({ page }).analyze();
  expect(duplicateResults.violations).toEqual([]);

  await page
    .getByLabel("Review reason")
    .fill("Verified the open unit and approved a controlled duplicate intake.");
  await page.getByRole("button", { name: "Record duplicate review" }).click();
  await expect(
    page.getByRole("status").filter({
      hasText:
        "Open duplicate approved for a controlled link to the existing stock record.",
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Confirm vehicle details" }),
  ).toBeEnabled();
  await page.getByRole("button", { name: "Confirm vehicle details" }).click();
  await expect(page.getByText("Step 3 of 3")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Allocate stock and add inventory" }),
  ).toHaveCount(0);
  await expect(page.getByLabel("Inventory location")).toHaveValue(
    "00000000-0000-4000-8000-000000000306",
  );
  await expect(page.getByLabel("Vehicle condition")).toHaveValue("used.ready");
  await expect(
    page.getByText(
      /no number is allocated; acquisition, odometer, price, and notes remain unchanged/u,
    ),
  ).toBeVisible();
  await expect(page.getByLabel("Advertised price (optional)")).toHaveCount(0);
  await expect(page.getByLabel("Public notes (optional)")).toHaveCount(0);
  await page
    .getByRole("button", { name: "Link request to existing stock" })
    .click();
  await expect(
    page.getByRole("heading", { name: "Existing inventory linked" }),
  ).toBeVisible();
  await expect(
    page.getByText(
      "This VIN request is linked to existing stock SYN-00120; no new stock number was allocated.",
    ),
  ).toBeVisible();
});

test("[M2-INV-AC-004][T-INV-002] surfaces a durable VIN retry with a mandatory reason", async ({
  page,
}) => {
  await page.goto(intakePreviewPath);
  await page
    .getByRole("textbox", { name: "VIN", exact: true })
    .fill("9FALR23ABCD456789");
  await page.getByRole("button", { name: "Start VIN decode" }).click();

  await expect(
    page.getByRole("heading", { name: "Retry available" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Retry decode" }),
  ).toBeDisabled();
  await page
    .getByLabel("Retry reason")
    .fill("Provider connection recovered; retry requested by the operator.");
  await page.getByRole("button", { name: "Retry decode" }).click();
  await expect(
    page.getByText("Decode complete", { exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Confirm vehicle details" }),
  ).toBeEnabled();
});

test("[M2-INV-AC-004][M2-INV-AC-005][T-INV-002][T-NUM-001][T-UX-001][T-UX-002] creates inventory from audited manual facts only after dead letter", async ({
  page,
}) => {
  await page.goto(intakePreviewPath);
  await expect(
    page.getByRole("heading", { name: "Continue with audited manual facts" }),
  ).toHaveCount(0);

  await page
    .getByRole("textbox", { name: "VIN", exact: true })
    .fill("9FALR23ABCD456789");
  await page.getByRole("button", { name: "Start VIN decode" }).click();
  await expect(page.getByText("Decode queued", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "Continue with audited manual facts" }),
  ).toHaveCount(0);

  await expect(
    page.getByRole("heading", { name: "Retry available" }),
  ).toBeVisible();
  const manualForm = page.getByRole("form", {
    name: "Continue with audited manual facts",
  });
  await expect(manualForm).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Retry decode" }),
  ).toBeVisible();
  await expect(
    manualForm.getByRole("button", {
      name: "Confirm manual facts and continue",
    }),
  ).toBeDisabled();

  await manualForm.getByLabel("Model year").fill("2019");
  await manualForm.getByLabel("Make").fill("Subaru");
  await manualForm.getByLabel("Model", { exact: true }).fill("Outback");
  await manualForm.getByLabel("Cylinders").fill("4");
  await manualForm.getByLabel("Horsepower").fill("182");
  await manualForm
    .getByLabel("Why manual facts are required")
    .fill("Provider exhausted its attempts; facts verified from registration.");
  await expect(
    manualForm.getByLabel("Existing vehicle relationship (optional)"),
  ).toHaveValue("");
  await expect(
    manualForm
      .getByLabel("Existing vehicle relationship (optional)")
      .locator("option"),
  ).toHaveCount(1);
  await manualForm.getByLabel(/I confirm these facts were checked/u).check();

  const manualOverflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(manualOverflow).toBe(false);
  const manualResults = await new AxeBuilder({ page }).analyze();
  expect(manualResults.violations).toEqual([]);

  await manualForm
    .getByRole("button", { name: "Confirm manual facts and continue" })
    .click();
  await expect(page.getByText("Step 3 of 3")).toBeVisible();
  await expect(page.getByLabel("Inventory location")).toHaveValue(
    "00000000-0000-4000-8000-000000000306",
  );
  await expect(page.getByLabel("Vehicle condition")).toHaveValue("used.ready");
  await expect(page.getByLabel("Active stock definition")).toHaveValue(
    "00000000-0000-4000-8000-000000000302",
  );
  await page.getByLabel("Advertised price (optional)").fill("24995.09");
  await page
    .getByRole("button", { name: "Create audited manual inventory" })
    .click();

  await expect(
    page.getByRole("heading", { level: 2, name: "Inventory added" }),
  ).toBeVisible();
  await expect(page.getByText(/Stock SYN-M0091 is ready/u)).toBeVisible();
  await expect(page.getByText("Decode complete", { exact: true })).toHaveCount(
    0,
  );
});

test("[M2-INV-AC-003][M2-INV-AC-004][T-INV-002][T-INV-003] forces a candidate-backed decision for audited manual intake", async ({
  page,
}) => {
  await page.goto(intakePreviewPath);
  await page
    .getByRole("textbox", { name: "VIN", exact: true })
    .fill("3SAMP34EFGH567890");
  await page.getByRole("button", { name: "Start VIN decode" }).click();

  const manualForm = page.getByRole("form", {
    name: "Continue with audited manual facts",
  });
  await expect(manualForm).toBeVisible();
  await expect(manualForm.getByText("Stock SYN-00120 · Active")).toBeVisible();
  const relationship = manualForm.getByLabel(
    "Existing vehicle relationship (optional)",
  );
  await expect(relationship).toHaveValue("override_open_duplicate");
  await expect(relationship.locator("option")).toHaveCount(1);

  await manualForm.getByLabel("Model year").fill("2023");
  await manualForm.getByLabel("Make").fill("Toyota");
  await manualForm.getByLabel("Model", { exact: true }).fill("RAV4");
  await manualForm
    .getByLabel("Why manual facts are required")
    .fill("Decoder failed; facts were verified against the registration.");
  await manualForm.getByLabel(/I confirm these facts were checked/u).check();
  await expect(
    manualForm.getByRole("button", {
      name: "Confirm manual facts and continue",
    }),
  ).toBeDisabled();
  await manualForm
    .getByLabel("Relationship reason")
    .fill("The VIN belongs to the active unit already in this workspace.");
  await manualForm
    .getByRole("button", { name: "Confirm manual facts and continue" })
    .click();

  await expect(page.getByText("Step 3 of 3")).toBeVisible();
  await expect(page.getByLabel("Advertised price (optional)")).toHaveCount(0);
  await page
    .getByRole("button", { name: "Link request to existing stock" })
    .click();
  await expect(
    page.getByRole("heading", { name: "Existing inventory linked" }),
  ).toBeVisible();
});

test("[T-I18N-001] localizes the intake and has no detectable accessibility violations", async ({
  page,
}) => {
  await page.goto(intakePreviewPath);
  const initialResults = await new AxeBuilder({ page }).analyze();
  expect(initialResults.violations).toEqual([]);

  await page.getByRole("button", { name: "Français" }).click();
  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  await expect(page).toHaveURL(/\/inventory\/new\?preview=inventory$/u);
  await expect(
    page.getByRole("heading", { level: 1, name: "Ajouter à l’inventaire" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Démarrer le décodage du NIV" }),
  ).toBeVisible();
  await expect(page.getByText("Étape 1 sur 3")).toBeVisible();
});
