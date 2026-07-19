// Stable test IDs: T-UX-001, T-UX-002, T-I18N-001.
// Migration evidence: UI-MIG-02, UI-MIG-04, UI-MIG-05, UI-MIG-06.
import AxeBuilder from "@axe-core/playwright";
import {
  expect,
  test,
  type Locator,
  type Page,
  type TestInfo,
} from "@playwright/test";

const previewPath = "/documents?preview=m4";
const localeContextPath =
  "/documents?preview=m4&workspace=10000000-0000-4000-8000-000000000401&access_token=drop-me";
const representativeVisualRoutes = [
  {
    name: "inventory",
    path: "/inventory?preview=inventory",
    readyText: "SYN-24018",
  },
  {
    name: "deal-detail",
    path: "/deals/10000000-0000-4000-8000-000000000801?preview=m3",
    readyText: "Maya Okonkwo",
  },
  {
    name: "documents",
    path: previewPath,
    readyText: "DOC-2026-00412",
  },
  {
    name: "configuration",
    path: "/configuration?preview=m4",
    readyText: "official_document",
  },
  {
    name: "exports",
    path: "/exports?preview=m4",
    readyText: "STK-1042",
  },
] as const;
const shellSelector = '[data-vynlo-ui="app-shell"]';
const themeStorageKey = "vynlo-theme";
const responsiveWidths = [320, 375, 414, 768, 1280] as const;
const accessibilityRoutes = [
  ...representativeVisualRoutes,
  {
    name: "inventory-intake",
    path: "/inventory/new?preview=inventory",
    readyText: null,
  },
] as const;

async function applyPresentationState(
  page: Page,
  state: { readonly locale: "en" | "fr"; readonly theme: "light" | "dark" },
) {
  await page.context().addCookies([
    {
      domain: "127.0.0.1",
      name: "vynlo_locale",
      path: "/",
      sameSite: "Lax",
      value: state.locale,
    },
  ]);
  await page.goto("/health");
  await page.evaluate(({ key, theme }) => localStorage.setItem(key, theme), {
    key: themeStorageKey,
    theme: state.theme,
  });
}

async function expectNoHorizontalOverflow(page: Page, label: string) {
  expect(
    await page.evaluate(() => {
      const viewportWidth = document.documentElement.clientWidth;
      const bodyOverflow =
        document.body.scrollWidth > document.body.clientWidth;
      const rootOverflow = document.documentElement.scrollWidth > viewportWidth;
      return {
        body: bodyOverflow,
        offenders:
          bodyOverflow || rootOverflow
            ? Array.from(document.body.querySelectorAll<HTMLElement>("*"))
                .filter((element) => {
                  const rectangle = element.getBoundingClientRect();
                  return (
                    rectangle.right > viewportWidth + 1 || rectangle.left < -1
                  );
                })
                .slice(0, 8)
                .map((element) => ({
                  className: element.className.toString().slice(0, 100),
                  clientWidth: element.clientWidth,
                  html: element.outerHTML.slice(0, 140),
                  left: Math.round(element.getBoundingClientRect().left),
                  right: Math.round(element.getBoundingClientRect().right),
                  scrollWidth: element.scrollWidth,
                  tag: element.tagName,
                }))
            : [],
        root: rootOverflow,
      };
    }),
    `horizontal overflow at ${label}`,
  ).toEqual({ body: false, offenders: [], root: false });
}

async function expectVisibleKeyboardFocus(target: Locator) {
  await expect(target).toBeFocused();
  expect(
    await target.evaluate((element) => {
      const style = window.getComputedStyle(element);
      const threePixelRing = /(?:^|\s)3px(?:\s|,)/u.test(style.boxShadow);
      return (
        (style.outlineStyle !== "none" &&
          Number.parseFloat(style.outlineWidth) >= 3) ||
        threePixelRing
      );
    }),
    "focused control must expose the immediate three-pixel Vynlo focus ring",
  ).toBe(true);
}

async function tabTo(page: Page, target: Locator, maximumTabs = 40) {
  for (let index = 0; index < maximumTabs; index += 1) {
    await page.keyboard.press("Tab");
    if (
      await target.evaluate(
        (element) => element === element.ownerDocument.activeElement,
      )
    ) {
      return;
    }
  }
  throw new Error("keyboard focus did not reach the requested Vynlo control");
}

async function undersizedTargets(page: Page) {
  return page.locator("body").evaluate((body) =>
    Array.from(
      body.querySelectorAll<HTMLElement>(
        'button, summary, a[href], input:not([type="hidden"]), select, textarea, [role="button"], [role="menuitem"], [role="menuitemradio"], [role="tab"]',
      ),
    ).flatMap((element) => {
      const effectiveTarget =
        (element instanceof HTMLInputElement &&
          (element.type === "checkbox" || element.type === "radio")) ||
        element.getAttribute("role") === "checkbox" ||
        element.getAttribute("role") === "radio" ||
        element.getAttribute("role") === "switch"
          ? (element.closest<HTMLElement>("label") ?? element)
          : element;
      const rectangle = effectiveTarget.getBoundingClientRect();
      const style = window.getComputedStyle(effectiveTarget);
      if (
        style.display === "none" ||
        style.visibility === "hidden" ||
        rectangle.width === 0 ||
        rectangle.height === 0 ||
        effectiveTarget.closest("nextjs-portal")
      ) {
        return [];
      }
      return rectangle.width < 44 || rectangle.height < 44
        ? [
            {
              height: Math.round(rectangle.height),
              label:
                element.getAttribute("aria-label") ??
                element.textContent?.trim().slice(0, 80) ??
                element.tagName,
              tag: element.tagName,
              width: Math.round(rectangle.width),
            },
          ]
        : [];
    }),
  );
}

async function expectNavigationLabelsOnOneLine(page: Page, width: number) {
  const wrappedLabels = await page
    .locator(
      `${shellSelector} nav a:visible span, ${shellSelector} [data-vynlo-ui="mobile-more-trigger"]:visible span`,
    )
    .evaluateAll((elements) =>
      elements.flatMap((element) => {
        const rectangle = element.getBoundingClientRect();
        const lineHeight = Number.parseFloat(
          window.getComputedStyle(element).lineHeight,
        );
        return Number.isFinite(lineHeight) &&
          rectangle.height > lineHeight * 1.5
          ? [element.textContent?.trim() ?? "unlabelled navigation item"]
          : [];
      }),
    );
  expect(wrappedLabels, `wrapped navigation labels at ${width}px`).toEqual([]);
}

function durationInSeconds(value: string) {
  const trimmed = value.trim();
  if (trimmed.endsWith("ms")) return Number.parseFloat(trimmed) / 1000;
  if (trimmed.endsWith("s")) return Number.parseFloat(trimmed);
  return 0;
}

async function prepareDeterministicCapture(page: Page) {
  await page.addStyleTag({
    content: `
      *, *::before, *::after {
        animation-delay: 0s !important;
        animation-duration: 0s !important;
        caret-color: transparent !important;
        transition-delay: 0s !important;
        transition-duration: 0s !important;
      }
      [data-sonner-toaster], nextjs-portal { display: none !important; }
    `,
  });
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all(
      Array.from(document.images).map(async (image) => {
        if (image.complete) return;
        await image.decode().catch(() => undefined);
      }),
    );
    document.documentElement.dataset.visualReady = "true";
  });
}

async function waitForWorkflowReady(
  page: Page,
  workflow: (typeof accessibilityRoutes)[number],
) {
  await expect(page.locator(shellSelector)).toBeVisible();
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  if (workflow.readyText) {
    await expect(page.locator("main")).toContainText(workflow.readyText, {
      timeout: 15_000,
    });
  }
}

async function captureVisualEvidence(
  page: Page,
  testInfo: TestInfo,
  workflow: (typeof representativeVisualRoutes)[number],
  width: 375 | 1440,
) {
  await page.clock.setFixedTime(new Date("2026-07-17T12:00:00.000Z"));
  await page.setViewportSize({ height: width === 375 ? 900 : 1000, width });
  await page.goto(workflow.path);
  await waitForWorkflowReady(page, workflow);
  await prepareDeterministicCapture(page);
  const name = `vynlo-${workflow.name}-${width}`;
  const screenshot = await page.screenshot({
    animations: "disabled",
    caret: "hide",
    fullPage: true,
  });
  await testInfo.attach(name, { body: screenshot, contentType: "image/png" });

  await expect(page).toHaveScreenshot(`${name}.png`, {
    animations: "disabled",
    caret: "hide",
    fullPage: true,
    maxDiffPixelRatio: 0.01,
  });
}

test("UI-MIG-02 persists light, dark, and system theme modes", async ({
  page,
}) => {
  await page.emulateMedia({ colorScheme: "light" });
  await page.goto(previewPath);
  const root = page.locator("html");
  const themeTrigger = page.locator('[data-vynlo-ui="theme-trigger"]');

  await expect(root).toHaveClass(/\blight\b/u);
  await themeTrigger.click();
  await page.getByRole("menuitemradio", { name: "Dark" }).click();
  await expect(root).toHaveClass(/\bdark\b/u);
  expect(
    await page.evaluate((key) => localStorage.getItem(key), themeStorageKey),
  ).toBe("dark");

  await page.reload();
  await expect(root).toHaveClass(/\bdark\b/u);
  await themeTrigger.click();
  await page.getByRole("menuitemradio", { name: "Light" }).click();
  await expect(root).toHaveClass(/\blight\b/u);

  await themeTrigger.click();
  await page.getByRole("menuitemradio", { name: "System" }).click();
  await page.emulateMedia({ colorScheme: "dark" });
  await expect(root).toHaveClass(/\bdark\b/u);
  expect(
    await page.evaluate((key) => localStorage.getItem(key), themeStorageKey),
  ).toBe("system");
});

test("UI-MIG-04 keeps the shared shell usable at every required width", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name !== "desktop-chromium",
    "The desktop project drives the explicit viewport matrix; touch has a dedicated project.",
  );
  for (const width of responsiveWidths) {
    for (const workflow of representativeVisualRoutes) {
      await page.setViewportSize({ height: width < 768 ? 900 : 1000, width });
      await page.goto(workflow.path);
      await waitForWorkflowReady(page, workflow);

      const currentDestinations = page.locator(
        `${shellSelector} [aria-current="page"]:visible`,
      );
      await expect(
        currentDestinations,
        `${workflow.name} must expose exactly one current destination at ${width}px`,
      ).toHaveCount(1);
      await expectNoHorizontalOverflow(page, `${workflow.name} at ${width}px`);
      await expectNavigationLabelsOnOneLine(page, width);

      const overflowPolicy = await page.evaluate(() => ({
        body: window.getComputedStyle(document.body).overflowX,
        root: window.getComputedStyle(document.documentElement).overflowX,
      }));
      expect(
        overflowPolicy,
        `root overflow policy for ${workflow.name} at ${width}px`,
      ).toEqual({ body: "clip", root: "clip" });

      if (width <= 414) {
        expect(
          await undersizedTargets(page),
          `undersized targets in ${workflow.name} at ${width}px`,
        ).toEqual([]);
        await expect(
          page.locator('[data-vynlo-ui="mobile-more-trigger"]'),
        ).toBeVisible();
      }
      if (width === 1280) {
        await expect(
          page.locator('[data-vynlo-ui="mobile-more-trigger"]'),
        ).toBeHidden();
      }
    }
  }
});

test("UI-MIG-04 validates the shell with a real coarse pointer", async ({
  page,
}, testInfo) => {
  test.skip(!testInfo.project.name.startsWith("mobile-touch"));
  await page.goto(previewPath);
  expect(
    await page.evaluate(() => matchMedia("(pointer: coarse)").matches),
  ).toBe(true);
  expect(await undersizedTargets(page)).toEqual([]);
});

test("UI-MIG-04 exposes a keyboard-safe mobile More sheet", async ({
  page,
}) => {
  await page.setViewportSize({ height: 900, width: 375 });
  await page.goto(previewPath);
  const moreTrigger = page.locator('[data-vynlo-ui="mobile-more-trigger"]');

  await tabTo(page, moreTrigger);
  await expectVisibleKeyboardFocus(moreTrigger);
  await page.keyboard.press("Enter");

  const sheet = page.getByRole("dialog");
  await expect(sheet).toBeVisible();
  await expect(
    sheet.getByRole("link", { name: "Configuration" }),
  ).toBeVisible();
  await expect(sheet.getByRole("link", { name: "Exports" })).toBeVisible();
  await expect(sheet.getByRole("link", { name: "System" })).toBeVisible();
  expect(
    await undersizedTargets(page),
    "sheet targets must remain 44px",
  ).toEqual([]);

  const focusable = sheet.locator(
    'a[href]:visible, button:visible, input:visible, select:visible, textarea:visible, [tabindex]:not([tabindex="-1"]):visible',
  );
  const focusableCount = await focusable.count();
  expect(focusableCount).toBeGreaterThan(1);
  const firstFocusable = focusable.first();
  const lastFocusable = focusable.last();
  await lastFocusable.focus();
  await page.keyboard.press("Tab");
  await expect(firstFocusable).toBeFocused();
  await page.keyboard.press("Shift+Tab");
  await expect(lastFocusable).toBeFocused();

  await page.keyboard.press("Escape");
  await expect(sheet).toBeHidden();
  await expect(moreTrigger).toBeFocused();
});

test("UI-MIG-04 exposes and activates the skip link before application chrome", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium");
  await page.setViewportSize({ height: 900, width: 1280 });
  await page.goto(previewPath);
  const skipLink = page.locator("a.skip-link");
  await page.keyboard.press("Tab");
  await expectVisibleKeyboardFocus(skipLink);
  await page.keyboard.press("Enter");
  await expect(page.locator("#m4-main")).toBeFocused();
});

test("UI-MIG-05 preserves route context in English and French", async ({
  page,
}) => {
  await page.setViewportSize({ height: 900, width: 375 });
  await page.goto(localeContextPath);
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await page.getByRole("button", { name: /Fran/u }).click();
  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  await expect(page).toHaveURL(
    /\/documents\?preview=m4&workspace=10000000-0000-4000-8000-000000000401$/u,
  );
  await expect(
    page.locator('[data-vynlo-ui="mobile-more-trigger"]'),
  ).toContainText("Plus");
  await page.getByRole("button", { name: "English" }).click();
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await expect(page).toHaveURL(
    /\/documents\?preview=m4&workspace=10000000-0000-4000-8000-000000000401$/u,
  );

  await page.getByRole("link", { name: "Deals", exact: true }).click();
  await expect(page).toHaveURL(
    /\/deals\?preview=m3&workspace=10000000-0000-4000-8000-000000000401$/u,
  );
  await expect(page).not.toHaveURL(/access_token/u);
});

test("UI-MIG-05 retains entity identity and safe context while changing locale", async ({
  page,
}) => {
  const entityPath =
    "/deals/10000000-0000-4000-8000-000000000801?preview=m3&workspace=10000000-0000-4000-8000-000000000301&access_token=drop-me";
  await page.goto(entityPath);
  await expect(page.getByText("Maya Okonkwo", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: /Fran/u }).click();
  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  await expect(page).toHaveURL(
    /\/deals\/10000000-0000-4000-8000-000000000801\?preview=m3&workspace=10000000-0000-4000-8000-000000000301$/u,
  );
  await expect(page).not.toHaveURL(/access_token/u);
});

test("UI-MIG-04 remounts M3 and M4 workspace-owned surfaces before showing new data", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium");
  for (const route of [
    "/people?preview=m3",
    "/documents?preview=m4",
  ] as const) {
    await page.goto(route);
    const workspace = page.getByRole("combobox", { name: /Workspace/u });
    await expect(workspace).toBeVisible();
    const options = await workspace
      .locator("option")
      .evaluateAll((elements) =>
        elements.map((element) => (element as HTMLOptionElement).value),
      );
    expect(options.length).toBeGreaterThan(1);
    await page
      .locator("main > :not(header)")
      .first()
      .evaluate((element) => {
        element.setAttribute("data-stale-workspace-probe", "true");
      });
    await workspace.selectOption(options[1]!);
    await expect(workspace).toHaveValue(options[1]!);
    await expect(
      page.locator('[data-stale-workspace-probe="true"]'),
    ).toHaveCount(0);
  }
});

test("UI-MIG-02 removes spatial motion when reduced motion is requested", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ height: 900, width: 375 });
  await page.goto(previewPath);
  await page.locator('[data-vynlo-ui="mobile-more-trigger"]').click();
  await expect(page.getByRole("dialog")).toBeVisible();
  const violations = await page.locator("body").evaluate((body) =>
    [body, ...Array.from(body.querySelectorAll<HTMLElement>("*"))]
      .filter((element) => {
        const rectangle = element.getBoundingClientRect();
        return rectangle.width > 0 && rectangle.height > 0;
      })
      .flatMap((element) => {
        const style = window.getComputedStyle(element);
        const transitionProperties = style.transitionProperty.split(",");
        const transitionDurations = style.transitionDuration
          .split(",")
          .map((duration) => {
            const trimmed = duration.trim();
            return trimmed.endsWith("ms")
              ? Number.parseFloat(trimmed) / 1000
              : Number.parseFloat(trimmed);
          });
        const longestTransition = Math.max(0, ...transitionDurations);
        const animationDurations = style.animationDuration
          .split(",")
          .map((duration) => {
            const trimmed = duration.trim();
            return trimmed.endsWith("ms")
              ? Number.parseFloat(trimmed) / 1000
              : Number.parseFloat(trimmed);
          });
        const longestAnimation = Math.max(0, ...animationDurations);
        const spatialTransition = transitionProperties.some((property) =>
          /transform|translate|scale|rotate/iu.test(property),
        );
        return longestTransition > 0.15 ||
          longestAnimation > 0.15 ||
          (spatialTransition && longestTransition > 0)
          ? [
              {
                animationDuration: style.animationDuration,
                element: element.outerHTML.slice(0, 120),
                transitionDuration: style.transitionDuration,
                transitionProperty: style.transitionProperty,
              },
            ]
          : [];
      }),
  );
  expect(violations).toEqual([]);

  // Exercise the parser used by this assertion so ms and s remain equivalent.
  expect(durationInSeconds("150ms")).toBe(durationInSeconds("0.15s"));
});

test("UI-MIG-02 limits overlay motion to opacity/transform for 120-220ms", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium");
  await page.setViewportSize({ height: 900, width: 375 });
  await page.goto(previewPath);
  await page.locator('[data-vynlo-ui="mobile-more-trigger"]').click();
  const motion = await page
    .locator('[data-slot="sheet-overlay"], [data-slot="sheet-content"]')
    .evaluateAll((elements) =>
      elements.map((element) => {
        const style = window.getComputedStyle(element);
        return {
          animationDuration: style.animationDuration,
          transitionDuration: style.transitionDuration,
          transitionProperty: style.transitionProperty,
        };
      }),
    );
  expect(motion.length).toBe(2);
  for (const style of motion) {
    const durations = [
      ...style.animationDuration.split(","),
      ...style.transitionDuration.split(","),
    ]
      .map(durationInSeconds)
      .filter((duration) => duration > 0);
    expect(Math.max(...durations)).toBeLessThanOrEqual(0.22);
    expect(Math.min(...durations)).toBeGreaterThanOrEqual(0.12);
    const activeTransitionProperties = style.transitionProperty
      .split(",")
      .map((property) => property.trim())
      .filter((property) => property !== "all" && property !== "none");
    expect(
      activeTransitionProperties.every(
        (property) => property === "opacity" || property === "transform",
      ),
    ).toBe(true);
  }
});

test("UI-MIG-02/05 has no serious or critical accessibility violations in both themes and locales", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium");
  for (const locale of ["en", "fr"] as const) {
    for (const theme of ["light", "dark"] as const) {
      const state = { locale, theme } as const;
      await applyPresentationState(page, state);
      await page.setViewportSize({ height: 1_000, width: 1_280 });
      for (const route of accessibilityRoutes) {
        await page.goto(route.path);
        await waitForWorkflowReady(page, route);
        await expect(page.locator("html")).toHaveAttribute("lang", locale);
        await expect(page.locator("html")).toHaveClass(
          new RegExp(`\\b${theme}\\b`, "u"),
        );
        const result = await new AxeBuilder({ page }).analyze();
        expect(
          result.violations.filter(
            ({ impact }) => impact === "critical" || impact === "serious",
          ),
          `${route.name} ${theme}/${locale} accessibility violations`,
        ).toEqual([]);
      }

      await page.setViewportSize({ height: 900, width: 375 });
      await page.goto(previewPath);
      await waitForWorkflowReady(page, representativeVisualRoutes[2]);
      await page.locator('[data-vynlo-ui="mobile-more-trigger"]').click();
      await expect(page.getByRole("dialog")).toBeVisible();
      const overlayResult = await new AxeBuilder({ page }).analyze();
      expect(
        overlayResult.violations.filter(
          ({ impact }) => impact === "critical" || impact === "serious",
        ),
        `open sheet ${theme}/${locale} accessibility violations`,
      ).toEqual([]);
    }
  }
});

test("UI-MIG-01 enforces ten deterministic visual baselines", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name !== "desktop-chromium",
    "The approved visual suite contains exactly ten desktop-Chromium baselines.",
  );
  await page.context().addCookies([
    {
      domain: "127.0.0.1",
      name: "vynlo_locale",
      path: "/",
      sameSite: "Lax",
      value: "en",
    },
  ]);
  await page.addInitScript(({ key }) => localStorage.setItem(key, "light"), {
    key: themeStorageKey,
  });
  for (const workflow of representativeVisualRoutes) {
    await captureVisualEvidence(page, testInfo, workflow, 375);
    await captureVisualEvidence(page, testInfo, workflow, 1440);
  }
});
