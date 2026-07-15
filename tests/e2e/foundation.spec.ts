import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

test("renders the accessible foundation shell without horizontal overflow", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText(
    "calm operating surface",
  );
  await expect(
    page.getByRole("navigation", { name: "Primary navigation" }),
  ).toBeVisible();
  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);
});

test("serves health endpoints and the PWA manifest", async ({ request }) => {
  const live = await request.get("/api/v1/health/live");
  expect(live.ok()).toBe(true);
  await expect(live.json()).resolves.toEqual({
    data: { service: "web", status: "ok" },
  });
  const ready = await request.get("/api/v1/health/ready");
  expect(ready.ok()).toBe(true);
  const manifest = await request.get("/manifest.webmanifest");
  expect(manifest.ok()).toBe(true);
});

test("has no automatically detectable accessibility violations", async ({
  page,
}) => {
  await page.goto("/");
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
