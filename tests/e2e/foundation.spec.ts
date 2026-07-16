import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

test("renders the accessible foundation shell without horizontal overflow", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "Workspace readiness",
  );
  await expect(
    page.getByRole("navigation", { name: "Primary navigation" }),
  ).toBeVisible();
  await expect(page.getByRole("link", { name: "Inventory" })).toHaveCount(0);
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
  await expect(manifest.json()).resolves.toMatchObject({
    display: "standalone",
    icons: expect.arrayContaining([
      expect.objectContaining({ sizes: "192x192" }),
      expect.objectContaining({ sizes: "512x512" }),
    ]),
  });
  const serviceWorker = await request.get("/sw.js");
  expect(serviceWorker.ok()).toBe(true);
  expect(serviceWorker.headers()["cache-control"]).toContain("no-cache");
  expect(serviceWorker.headers()["service-worker-allowed"]).toBe("/");
  expect(live.headers()["x-content-type-options"]).toBe("nosniff");
});

test("switches between English and French without changing machine keys", async ({
  page,
}) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Français" }).click();
  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "État de préparation",
  );
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
});

test("surfaces connectivity loss and promises no offline writes", async ({
  context,
  page,
}) => {
  await page.goto("/");
  await context.setOffline(true);
  await expect(
    page.getByText("You are offline", { exact: true }),
  ).toBeVisible();
  await expect(page.getByText(/never queues offline writes/i)).toBeVisible();
  await context.setOffline(false);
});

test("has no automatically detectable accessibility violations", async ({
  page,
}) => {
  await page.goto("/");
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});

test("provides an accessible invite-only sign-in form at phone and desktop widths", async ({
  page,
}) => {
  await page.goto("/login");

  await expect(
    page.getByRole("heading", { level: 1, name: "Enter your workspace" }),
  ).toBeVisible();
  await expect(page.getByText("Invite-only access")).toBeVisible();
  await expect(page.getByLabel("Work email")).toBeVisible();
  await expect(page.getByLabel("Password (optional)")).toBeVisible();
  await expect(
    page.getByText(/public registration is disabled/i),
  ).toBeVisible();

  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth >
      document.documentElement.clientWidth,
  );
  expect(overflow).toBe(false);

  for (const control of await page
    .locator("main input, main button, main a")
    .all()) {
    const box = await control.boundingBox();
    if (box) {
      expect(box.height).toBeGreaterThanOrEqual(44);
    }
  }

  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});

test("redirects unauthenticated operations access to invite-only sign-in", async ({
  page,
}) => {
  await page.goto("/operations");
  await expect(page).toHaveURL(/\/login$/);
  await expect(
    page.getByRole("heading", { level: 1, name: "Enter your workspace" }),
  ).toBeVisible();
});

test("fails closed on malformed invitation routing context", async ({
  page,
}) => {
  await page.goto("/login?invitation=not-a-uuid");
  await expect(
    page
      .getByRole("status")
      .filter({ hasText: /invitation link is incomplete/i }),
  ).toBeVisible();
  await expect(page).toHaveURL(/\/login\?invitation=not-a-uuid$/);
});
