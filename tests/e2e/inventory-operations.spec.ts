import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const inventoryId = "00000000-0000-4000-8000-000000000211";
const previewPath = `/inventory/${inventoryId}?preview=inventory`;

test("T-INV-004 / T-UX-001 renders a phone-usable inventory dossier without overflow", async ({
  page,
}) => {
  await page.goto(previewPath);

  await expect(
    page.getByRole("heading", { level: 1, name: "2024 Volvo XC60 Plus" }),
  ).toBeVisible();
  await expect(page.getByText("SYN-24018")).toBeVisible();
  await expect(
    page.getByRole("heading", { level: 2, name: "Inventory details" }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { level: 2, name: "Cost ledger" }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { level: 2, name: "Vehicle facts" }),
  ).toBeVisible();
  await expect(page.getByLabel("Cost category")).toHaveValue(
    "00000000-0000-4000-8000-000000000251",
  );
  await expect(page.getByLabel("Destination location")).toHaveValue(
    "00000000-0000-4000-8000-000000000221",
  );

  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);

  for (const control of await page
    .locator("main input, main select, main textarea, main button, main nav a")
    .all()) {
    const box = await control.boundingBox();
    if (box) expect(box.height).toBeGreaterThanOrEqual(44);
  }

  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});

test("T-INV-004 / T-COST-001 simulates versioned details, transfer, cost, reversal, and fact correction", async ({
  page,
}) => {
  await page.goto(previewPath);

  await page.getByLabel("Advertised price").fill("55995.00");
  await page.getByLabel("Public notes").fill("Prepared for bilingual listing.");
  await page.getByRole("button", { name: "Save details" }).click();
  await expect(
    page.getByRole("status").filter({ hasText: "Changes saved." }),
  ).toBeVisible();
  await expect(page.getByText("7", { exact: true }).first()).toBeVisible();

  const locationSection = page.locator(
    'section[aria-labelledby="inventory-location-heading"]',
  );
  await locationSection
    .getByLabel("Destination location")
    .selectOption("00000000-0000-4000-8000-000000000222");
  await locationSection
    .getByLabel("Reason")
    .fill("Move completed after inspection.");
  await locationSection
    .getByRole("button", { name: "Transfer location" })
    .click();
  await expect(locationSection.locator("header p")).toHaveText("North lot");

  const costSection = page.locator(
    'section[aria-labelledby="inventory-cost-heading"]',
  );
  await costSection.getByLabel("Amount").fill("325.40");
  await costSection.getByLabel("Incurred on").fill("2026-07-16");
  await costSection.getByLabel("Description").fill("Synthetic tire service");
  await costSection.getByRole("button", { name: "Post cost" }).click();
  await expect(costSection.getByText("Synthetic tire service")).toBeVisible();

  await costSection.getByLabel("Reversed on").fill("2026-07-16");
  await costSection
    .getByLabel("Reason")
    .fill("Duplicate synthetic vendor invoice.");
  await costSection.getByRole("button", { name: "Reverse cost" }).click();
  await expect(
    costSection.locator('article[data-status="reversed"]').filter({
      hasText: "Synthetic tire service",
    }),
  ).toBeVisible();

  const facts = page.locator(
    'aside[aria-labelledby="inventory-facts-heading"]',
  );
  await facts.getByLabel("Make").fill("Volvo Cars");
  await facts
    .getByLabel("Reason")
    .fill("Corrected from registration paperwork.");
  await facts.getByRole("button", { name: "Save fact correction" }).click();
  await expect(
    page.getByRole("heading", { level: 1, name: "2024 Volvo Cars XC60 Plus" }),
  ).toBeVisible();
});

test("T-I18N-001 preserves preview context and localizes the operator surface in French", async ({
  page,
}) => {
  await page.goto(previewPath);
  await page.getByRole("button", { name: "Français" }).click();

  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  await expect(page).toHaveURL(
    new RegExp(`/inventory/${inventoryId}\\?.*preview=inventory`, "u"),
  );
  await expect(
    page.getByRole("heading", { level: 2, name: "Détails de l’inventaire" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Enregistrer les détails" }),
  ).toBeVisible();
  await expect(page.getByLabel("Catégorie de coût")).toBeVisible();
});

test("T-SEARCH-001 round-trips an active location through an owned saved view", async ({
  page,
}) => {
  await page.goto("/inventory?preview=inventory");

  await page.getByLabel("Saved views").selectOption({
    label: "Showroom inventory",
  });
  await page.getByRole("button", { name: "Apply saved view" }).click();
  await expect(page.getByLabel("Location")).toHaveValue(
    "00000000-0000-4000-8000-000000000221",
  );
  await expect(page.getByText("1 vehicle", { exact: true })).toBeVisible();

  await page
    .getByLabel("Location")
    .selectOption("00000000-0000-4000-8000-000000000222");
  await page
    .getByRole("region", { name: "Find inventory" })
    .getByRole("combobox", { exact: true, name: "Status" })
    .selectOption("pending");
  await page.getByRole("button", { name: "Apply filters" }).click();
  await expect(page.getByText("1 vehicle", { exact: true })).toBeVisible();

  await page.getByRole("button", { name: "Update selected view" }).click();
  await expect(page.getByText("Selected view updated.")).toBeVisible();
  await page.getByRole("button", { name: "Apply saved view" }).click();
  await expect(page.getByLabel("Location")).toHaveValue(
    "00000000-0000-4000-8000-000000000222",
  );

  await page.getByRole("button", { name: "Archive view" }).click();
  await expect(page.getByText("Saved view archived.")).toBeVisible();
  await expect(
    page.getByLabel("Saved views").getByRole("option", {
      name: "Showroom inventory",
    }),
  ).toHaveCount(0);
});
