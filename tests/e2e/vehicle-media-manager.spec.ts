import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const inventoryUnitId = "00000000-0000-4000-8000-000000000211";
const previewPath = `/inventory/${inventoryUnitId}/media?preview=inventory`;

test("T-MED-004 / T-MED-005 / T-UX-001 manages retry, captions, order, cover, and archive on a phone and desktop", async ({
  page,
}) => {
  await page.goto(previewPath);

  await expect(
    page.getByRole("heading", { level: 1, name: "Photo order & status" }),
  ).toBeVisible();
  await expect(
    page.getByText("2 active photos", { exact: true }),
  ).toBeVisible();

  const failedPhoto = page.getByRole("article", { name: "Photo 2" });
  await expect(failedPhoto.getByText("Processing failed")).toBeVisible();
  await failedPhoto.getByRole("button", { name: "Retry processing" }).click();
  await expect(
    failedPhoto.getByText("Processing", { exact: true }),
  ).toBeVisible();
  await expect(failedPhoto.getByText("Ready", { exact: true })).toBeVisible();

  const firstPhoto = page.getByRole("article", { name: "Photo 1" });
  await firstPhoto.getByLabel("Caption").fill("Front showroom angle");
  await firstPhoto.getByRole("button", { name: "Save caption" }).click();
  await expect(page.getByText("Saved", { exact: true })).toBeAttached();

  await page.getByRole("button", { name: "Move photo up: Photo 2" }).click();
  await expect(
    page.getByRole("article", { name: "Photo 1" }).getByLabel("Caption"),
  ).toHaveValue("Driver side");

  const promotedPhoto = page.getByRole("article", { name: "Photo 1" });
  await promotedPhoto.getByRole("button", { name: "Use as cover" }).click();
  await expect(
    promotedPhoto.getByText("Cover photo", { exact: true }),
  ).toBeVisible();

  await promotedPhoto.getByRole("button", { name: "Archive photo" }).click();
  await promotedPhoto
    .getByLabel("Archive reason")
    .fill("Superseded by the approved showroom angle");
  await promotedPhoto.getByRole("button", { name: "Confirm archive" }).click();

  await expect(
    page.getByText("1 active photos", { exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("article")).toHaveCount(1);
  await expect(
    page
      .getByRole("article", { name: "Photo 1" })
      .getByText("Cover photo", { exact: true }),
  ).toBeVisible();
});

test("T-MED-003 / T-MED-004 adds another photo through the quarantined durable upload flow", async ({
  page,
}) => {
  await page.goto(previewPath);

  const uploader = page.getByRole("region", { name: "Add another photo" });
  await uploader.getByLabel("Choose a vehicle photo").setInputFiles({
    buffer: Buffer.from("synthetic-vynlo-media-manager-photo"),
    mimeType: "image/jpeg",
    name: "showroom-rear.jpg",
  });

  await expect(uploader).toHaveAttribute("data-phase", "verification_queued");
  await expect(
    uploader.getByText("Private upload complete", { exact: true }),
  ).toBeVisible();
  await expect(
    uploader.getByText("Verification queued", { exact: true }).first(),
  ).toBeVisible();
  await expect(uploader.locator('[data-job-status="queued"]')).toHaveText(
    "Queued",
  );
  await expect(
    page.getByText("3 active photos", { exact: true }),
  ).toBeVisible();
});

test("T-I18N-001 keeps media management localized in French", async ({
  page,
}) => {
  await page.goto(previewPath);
  await page.getByRole("button", { name: "Français" }).click();

  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  await expect(page).toHaveURL(
    new RegExp(`/inventory/${inventoryUnitId}/media\\?preview=inventory$`, "u"),
  );
  await expect(
    page.getByRole("heading", {
      level: 1,
      name: "Ordre et état des photos",
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Relancer le traitement" }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { level: 2, name: "Ajouter une autre photo" }),
  ).toBeVisible();
  const uploader = page.getByRole("region", {
    name: "Ajouter une autre photo",
  });
  await uploader.getByLabel("Choisir une photo du véhicule").setInputFiles({
    buffer: Buffer.from("synthetic-vynlo-french-media-manager-photo"),
    mimeType: "image/jpeg",
    name: "vue-arriere.jpg",
  });
  await expect(uploader).toHaveAttribute("data-phase", "verification_queued");
  await expect(uploader.locator('[data-job-status="queued"]')).toHaveText(
    "En file d’attente",
  );
});

test("T-UX-001 / T-UX-002 has no page overflow, undersized controls, or automatic accessibility violations", async ({
  page,
}) => {
  await page.goto(previewPath);
  await expect(page.getByRole("article")).toHaveCount(2);

  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);

  for (const control of await page
    .locator(
      'main input:not([type="file"]), main textarea, main button, main a',
    )
    .all()) {
    const box = await control.boundingBox();
    if (box) expect(Math.round(box.height)).toBeGreaterThanOrEqual(44);
  }
  const pickerBox = await page
    .locator(".vehicle-photo-upload__picker")
    .boundingBox();
  expect(Math.round(pickerBox?.height ?? 0)).toBeGreaterThanOrEqual(44);

  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
