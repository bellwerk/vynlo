import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const documentId = "40000000-0000-4000-8000-000000000403";

const previewRoutes = [
  "/documents?preview=m4",
  `/documents/${documentId}?preview=m4`,
  "/configuration?preview=m4",
  "/exports?preview=m4",
] as const;

test("T-UX-001 keeps every M4 workbench phone-usable without overflow", async ({
  page,
}) => {
  await page.setViewportSize({ height: 900, width: 360 });
  for (const route of previewRoutes) {
    await page.goto(route);
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    expect(
      await page.evaluate(
        () =>
          document.documentElement.scrollWidth >
          document.documentElement.clientWidth,
      ),
      `horizontal overflow at ${route}`,
    ).toBe(false);
  }
});

test("T-DOC-001..006 validates, previews without a number, then confirms official allocation", async ({
  page,
}) => {
  await page.setViewportSize({ height: 900, width: 360 });
  await page.goto("/documents?preview=m4");

  await page
    .getByLabel("Location ID")
    .fill("40000000-0000-4000-8000-000000000421");
  await page
    .getByLabel("Seller legal entity ID")
    .fill("40000000-0000-4000-8000-000000000422");
  await page
    .getByLabel("Customer party ID")
    .fill("40000000-0000-4000-8000-000000000423");
  await page
    .getByLabel("Line items")
    .fill(
      '[{"description":"Synthetic fee","quantity":1,"unit_amount_minor":10000}]',
    );
  await page
    .getByRole("button", { name: "Validate fields and dependencies" })
    .click();
  await expect(
    page.getByText("Every required gate passed", { exact: false }),
  ).toBeVisible();

  const preview = page.getByRole("button", {
    name: "Generate unnumbered preview",
  });
  await expect(preview).toBeEnabled();
  await preview.click();
  await expect(
    page.getByRole("definition").filter({ hasText: "—" }).first(),
  ).toBeVisible();

  const official = page.getByRole("button", {
    name: "Allocate number and generate official PDF",
  });
  await expect(official).toBeDisabled();
  await page.getByLabel("Reason").fill("Customer approved exact preview");
  await page
    .getByLabel(
      "I understand an official number will be allocated permanently.",
    )
    .check();
  await expect(official).toBeEnabled();
  await official.click();
  await expect(
    page.getByRole("heading", { name: "DOC-2026-00413" }),
  ).toBeVisible();
});

test("T-DOC-005..006 exposes exact files, jobs, lineage, and guarded actions", async ({
  page,
}) => {
  await page.goto(`/documents/${documentId}?preview=m4`);
  for (const heading of [
    "Immutable files",
    "Render job history",
    "Lineage",
    "Upload signed scan",
  ]) {
    await expect(page.getByRole("heading", { name: heading })).toBeVisible();
  }
  await expect(
    page.getByRole("button", { name: "Mark document signed" }),
  ).toBeDisabled();
  await expect(
    page.getByRole("button", { name: "Void official document" }),
  ).toBeDisabled();
  await expect(page.getByText("DOC-2026-00412.pdf")).toBeVisible();
});

test("T-CALC-001 / T-TAX-001 / T-EXP-001 exposes lifecycle, reports, and persistent jobs", async ({
  page,
}) => {
  await page.goto("/configuration?preview=m4");
  for (const heading of [
    "Numbering",
    "Calculations",
    "Tax packs",
    "Approval evidence",
  ]) {
    await expect(page.getByRole("heading", { name: heading })).toBeVisible();
  }
  await expect(page.getByLabel("Deal ID for official evidence")).toHaveCount(2);
  await expect(
    page.getByText(
      "When a deal ID is provided, the server derives the calculation and tax inputs from the current deal and ignores the JSON input fields below.",
    ),
  ).toHaveCount(2);

  await page.goto("/exports?preview=m4");
  await expect(
    page.getByRole("tab", { name: "Inventory aging" }),
  ).toHaveAttribute("aria-selected", "true");
  await expect(page.getByText("2024 Polestar 2")).toBeVisible();
  await page.getByLabel("Export reason").fill("Month-end operations review");
  await page.getByRole("button", { name: "Generate export" }).click();
  await expect(page.getByText("Latest export run")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Download verified file" }),
  ).toBeVisible({ timeout: 5_000 });
});

test("T-UX-002 has no automatically detectable accessibility violations", async ({
  page,
}) => {
  await page.setViewportSize({ height: 900, width: 360 });
  for (const route of previewRoutes) {
    await page.goto(route);
    await expect(page.locator("main")).toBeVisible();
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations, `accessibility violations at ${route}`).toEqual(
      [],
    );
  }
});
