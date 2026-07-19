import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const previewPath = "/inventory?preview=inventory";

test("T-SEARCH-001 / T-UX-001 renders mobile cards and a desktop table without page overflow", async ({
  page,
}, testInfo) => {
  await page.goto(previewPath);

  await expect(
    page.getByRole("heading", { level: 1, name: "Inventory" }),
  ).toBeVisible();
  await expect(
    page.getByText("Development preview · synthetic inventory"),
  ).toBeVisible();
  await expect(page.getByText("3 vehicles", { exact: true })).toBeVisible();

  const mobileCards = page.getByRole("list", { name: "Inventory results" });
  const desktopTable = page.getByRole("table", { name: "Inventory results" });
  if (testInfo.project.name === "mobile-touch-360") {
    await expect(mobileCards).toBeVisible();
    await expect(mobileCards.getByRole("article")).toHaveCount(3);
    await expect(desktopTable).toBeHidden();
  } else {
    await expect(mobileCards).toBeHidden();
    await expect(desktopTable).toBeVisible();
    await expect(desktopTable.locator("tbody tr")).toHaveCount(3);
  }

  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);

  for (const control of await page
    .locator("main input, main select, main button")
    .all()) {
    const box = await control.boundingBox();
    if (box) expect(box.height).toBeGreaterThanOrEqual(44);
  }
});

test("T-SEARCH-001 filters synthetic results, exposes empty state, and saves a view", async ({
  page,
}, testInfo) => {
  await page.goto(previewPath);

  await page.getByLabel("Search inventory").fill("Transit");
  await page.getByRole("button", { name: "Apply filters" }).click();
  await expect(page.getByText("1 vehicle", { exact: true })).toBeVisible();

  if (testInfo.project.name === "mobile-touch-360") {
    await expect(
      page
        .getByRole("list", { name: "Inventory results" })
        .getByRole("heading", { name: "2022 Ford Transit" }),
    ).toBeVisible();
  } else {
    await expect(
      page
        .getByRole("table", { name: "Inventory results" })
        .getByText("2022 Ford Transit"),
    ).toBeVisible();
  }

  await page.getByRole("button", { name: "Save current view" }).click();
  await expect(page.getByText("Current view saved privately.")).toBeVisible();

  await page.getByLabel("Search inventory").fill("not-in-stock");
  await page.getByRole("button", { name: "Apply filters" }).click();
  await expect(
    page.getByRole("heading", { name: "No inventory matches this view" }),
  ).toBeVisible();
  await expect(page.getByText("0 vehicles", { exact: true })).toBeVisible();

  await page.getByRole("button", { name: "Clear filters" }).click();
  await expect(page.getByText("3 vehicles", { exact: true })).toBeVisible();
});

test("T-I18N-001 keeps the inventory preview and copy localized in French", async ({
  page,
}) => {
  await page.goto(previewPath);
  await page.getByRole("button", { name: "Français" }).click();

  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  await expect(
    page.getByRole("heading", { level: 1, name: "Inventaire" }),
  ).toBeVisible();
  await expect(page).toHaveURL(/\/inventory\?preview=inventory$/u);
  await expect(
    page.getByText("Aperçu de développement · inventaire synthétique"),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Appliquer les filtres" }),
  ).toBeVisible();
});

test("T-UX-002 has no automatically detectable accessibility violations", async ({
  page,
}) => {
  await page.goto(previewPath);
  await expect(page.getByText("3 vehicles", { exact: true })).toBeVisible();

  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
