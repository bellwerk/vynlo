import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Locator, type Page } from "@playwright/test";

const leadId = "10000000-0000-4000-8000-000000000401";
const partyId = "10000000-0000-4000-8000-000000000501";
const dealId = "10000000-0000-4000-8000-000000000801";

const previewRoutes = [
  "/people?preview=m3",
  "/people/leads/new?preview=m3",
  `/people/leads/${leadId}?preview=m3`,
  "/people/parties?preview=m3",
  `/people/parties/${partyId}?preview=m3`,
  "/people/tasks?preview=m3",
  "/people/appointments?preview=m3",
  "/deals?preview=m3",
  "/deals/new?preview=m3",
  `/deals/${dealId}?preview=m3`,
  `/deals/${dealId}/trade-ins?preview=m3`,
  `/deals/${dealId}/finance?preview=m3`,
  `/deals/${dealId}/payments?preview=m3`,
] as const;

const frenchPreviewRoutes = [
  { route: "/people?preview=m3", text: "Suivi des clients" },
  { route: "/people/leads/new?preview=m3", text: "Nouveau prospect" },
  {
    route: `/people/leads/${leadId}?preview=m3`,
    text: "Prochaine action",
  },
  { route: "/people/parties?preview=m3", text: "Nouveau client" },
  {
    route: `/people/parties/${partyId}?preview=m3`,
    text: "Profil typé",
  },
  { route: "/people/tasks?preview=m3", text: "Tâches" },
  { route: "/people/appointments?preview=m3", text: "Rendez-vous" },
  { route: "/deals?preview=m3", text: "Espace du dossier" },
  { route: "/deals/new?preview=m3", text: "Nouveau dossier" },
  {
    route: `/deals/${dealId}?preview=m3`,
    text: "Libérer le participant",
  },
  {
    route: `/deals/${dealId}/trade-ins?preview=m3`,
    text: "Échange",
  },
  {
    route: `/deals/${dealId}/finance?preview=m3`,
    text: "Financement externe",
  },
  {
    route: `/deals/${dealId}/payments?preview=m3`,
    text: "Registre des transactions ponctuelles",
  },
] as const;

async function tabTo(page: Page, target: Locator, maximumTabs = 80) {
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
  throw new Error(`keyboard focus did not reach ${await target.innerText()}`);
}

async function expectVisibleKeyboardFocus(target: Locator) {
  await expect(target).toBeFocused();
  expect(
    await target.evaluate((element) => {
      const style = window.getComputedStyle(element);
      return (
        (style.outlineStyle !== "none" && parseFloat(style.outlineWidth) > 0) ||
        style.boxShadow !== "none"
      );
    }),
  ).toBe(true);
}

test("T-UX-001 / T-CRM-001 / T-DEAL-001 keeps every M3 route within the viewport", async ({
  page,
}) => {
  for (const route of previewRoutes) {
    await page.goto(route);
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.locator("main")).toBeVisible();
    const overflow = await page.evaluate(
      () =>
        document.documentElement.scrollWidth >
        document.documentElement.clientWidth,
    );
    expect(overflow, `horizontal overflow at ${route}`).toBe(false);
  }
  await page.setViewportSize({ height: 800, width: 320 });
  await page.goto("/deals/new?preview=m3");
  expect(
    await page.evaluate(
      () =>
        document.documentElement.scrollWidth >
        document.documentElement.clientWidth,
    ),
    "horizontal overflow at 320px",
  ).toBe(false);

  for (const width of [320, 360]) {
    await page.setViewportSize({ height: 800, width });
    for (const route of [
      "/people/parties?preview=m3",
      `/people/parties/${partyId}?preview=m3`,
      `/deals/${dealId}/trade-ins?preview=m3`,
      `/deals/${dealId}/finance?preview=m3`,
      `/deals/${dealId}/payments?preview=m3`,
    ]) {
      await page.goto(route);
      expect(
        await page.evaluate(
          () =>
            document.documentElement.scrollWidth >
            document.documentElement.clientWidth,
        ),
        `horizontal overflow at ${width}px on ${route}`,
      ).toBe(false);
    }
  }
});

test("T-CRM-002 requires a lost reason and preserves lead context through conversion", async ({
  page,
}) => {
  await page.goto(`/people/leads/${leadId}?preview=m3`);

  await expect(
    page.getByRole("button", { name: "Convert to deal" }),
  ).toBeEnabled();

  await page.getByLabel("Next state").selectOption("qualified__lost");
  await expect(page.getByLabel("Reason for closing lost *")).toHaveAttribute(
    "required",
    "",
  );
  await page.getByLabel("Reason for closing lost *").fill("Timing changed");
  await page.getByRole("button", { name: "Move lead" }).click();
  await expect(
    page.getByRole("definition").filter({ hasText: /^Lost$/u }),
  ).toBeVisible();

  await expect(
    page.getByRole("button", { name: "Convert to deal" }),
  ).toBeDisabled();
  await page.getByRole("button", { name: /Fran/u }).click();
  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  const frenchTransition = page
    .locator("form")
    .filter({ has: page.locator("select") })
    .first();
  await frenchTransition.locator("select").selectOption("qualified__lost");
  await frenchTransition
    .locator('input[name="reason"]')
    .fill("Client indisponible");
  await frenchTransition.locator('button[type="submit"]').click();
  await expect(
    page.getByRole("definition").filter({ hasText: /^Perdu$/u }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Convertir en dossier" }),
  ).toBeDisabled();
});

test("T-CRM-003 exposes phone-usable typed party and privacy workflows", async ({
  page,
}) => {
  await page.setViewportSize({ height: 900, width: 360 });
  await page.goto("/people/parties?preview=m3");
  await page.locator("summary").filter({ hasText: "New party" }).click();
  await page.getByLabel("Party type *").selectOption("organization");
  await expect(page.getByLabel("Legal name *")).toBeVisible();
  await expect(page.getByLabel("Registration name")).toBeVisible();

  await page.goto(`/people/parties/${partyId}?preview=m3`);
  for (const heading of [
    "Typed profile",
    "Contact details",
    "Addresses",
    "Relationships",
    "Communication preferences",
    "Restricted identifiers",
    "Archive party",
  ]) {
    await expect(page.getByRole("heading", { name: heading })).toBeVisible();
  }
  await expect(
    page.getByLabel("Reason for restricted identifier access *").first(),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Reveal restricted identifier" }),
  ).toBeVisible();
});

test("T-DEAL-002 uses a phone-usable step sequence and explicit trade-in separation", async ({
  page,
}) => {
  await page.goto("/deals/new?preview=m3");
  await expect(page.getByTestId("T-DEAL-create-step")).toContainText(
    "Step 1 / 4",
  );

  for (let index = 0; index < 3; index += 1) {
    await page.getByRole("button", { name: "Continue" }).click();
  }
  await expect(page.getByText("Step 4 / 4")).toBeVisible();
  await page.getByRole("button", { name: "Create deal" }).click();
  await expect(page).toHaveURL(
    new RegExp(`/deals/${dealId}\\?preview=m3$`, "u"),
  );

  await page.goto(`/deals/${dealId}/trade-ins?preview=m3`);
  const addTradeIn = page.getByRole("button", { name: "Add trade-in" });
  await expect(addTradeIn).toBeDisabled();
  await page.getByLabel("Confirm resulting inventory separately").check();
  await expect(addTradeIn).toBeEnabled();
});

test("T-CRM-001 / T-DEAL-001 / T-UX-001 exposes retry-safe task, appointment, and deal-child controls", async ({
  page,
}) => {
  await page.setViewportSize({ height: 900, width: 360 });
  await page.goto("/people/tasks?preview=m3");
  await page.locator("summary").filter({ hasText: "Cancel task" }).click();
  await page.getByLabel("Reason for cancelling the task *").fill("Duplicate");
  await page.getByRole("button", { name: "Cancel task" }).click();
  await expect(page.getByText("Cancel", { exact: true })).toBeVisible();

  await page.goto("/people/appointments?preview=m3");
  await page
    .locator("summary")
    .filter({ hasText: "Update appointment" })
    .click();
  await page.getByLabel("Next state *").selectOption("no_show");
  await page
    .getByLabel("Reason for cancellation or no-show *")
    .fill("Customer did not arrive");
  await page.getByRole("button", { name: "Update appointment" }).click();
  await expect(page.getByText("No-show", { exact: true })).toBeVisible();

  await page.goto(`/deals/${dealId}?preview=m3`);
  await expect(
    page.getByRole("button", { name: "Release participant" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Release inventory unit" }),
  ).toBeVisible();
  await expect(
    page.locator("summary").filter({ hasText: "Update line item" }),
  ).toBeVisible();
});

test("T-DEAL-002 / T-FIN-001 / T-UX-001 exposes versioned trade-in and finance follow-up controls", async ({
  page,
}) => {
  await page.setViewportSize({ height: 900, width: 360 });
  await page.goto(`/deals/${dealId}/trade-ins?preview=m3`);
  await expect(
    page.locator("summary").filter({ hasText: "Edit trade-in" }),
  ).toBeVisible();
  await expect(
    page
      .locator("summary")
      .filter({ hasText: "Confirm resulting inventory unit" }),
  ).toBeVisible();

  await page.goto(`/deals/${dealId}/finance?preview=m3`);
  await expect(
    page.locator("summary").filter({ hasText: "Update finance application" }),
  ).toBeVisible();
  await expect(
    page.locator("summary").filter({ hasText: "Change finance status" }),
  ).toBeVisible();
  await page
    .locator("summary")
    .filter({ hasText: "Lender conditions" })
    .click();
  await expect(
    page.locator("summary").filter({ hasText: "Replace or satisfy condition" }),
  ).toBeVisible();
});

test("T-FIN-001 / T-PAY-001 labels external finance and supports one-time settlement", async ({
  page,
}) => {
  await page.goto(`/deals/${dealId}/finance?preview=m3`);
  await expect(page.getByTestId("T-FIN-workbench")).toContainText(
    "Lender-reported terms only",
  );
  await expect(page.getByTestId("T-FIN-workbench")).toContainText(
    "does not calculate",
  );

  await page.goto(`/deals/${dealId}/payments?preview=m3`);
  await page.getByRole("button", { name: "Settle" }).click();
  await expect(page.getByText("Settled", { exact: true })).toBeVisible();
  await page
    .locator("summary")
    .filter({ hasText: "Record correction" })
    .click();
  await expect(page.getByLabel("Reason for correction *")).toBeVisible();
});

test("T-I18N-001 keeps the current preview route and finance limits in French", async ({
  page,
}) => {
  await page.goto(`/deals/${dealId}/finance?preview=m3`);
  await page.getByRole("button", { name: "Français" }).click();

  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  await expect(page).toHaveURL(
    new RegExp(`/deals/${dealId}/finance\\?preview=m3$`, "u"),
  );
  await expect(
    page.getByRole("heading", { level: 1, name: "Financement externe" }),
  ).toBeVisible();
  await expect(page.getByTestId("T-FIN-workbench")).toContainText(
    "Conditions déclarées par le prêteur seulement",
  );
});

test("T-I18N-001 renders route-specific French content on every M3 operator route", async ({
  page,
}) => {
  for (const { route, text } of frenchPreviewRoutes) {
    await page.goto(route);
    await page.getByRole("button", { name: "Français" }).click();
    await expect(page.locator("html"), `language at ${route}`).toHaveAttribute(
      "lang",
      "fr",
    );
    await expect(
      page.getByRole("heading", { level: 1 }),
      `French heading at ${route}`,
    ).toBeVisible();
    await expect(
      page.locator("main").getByText(text, { exact: false }).first(),
      `route-specific French content at ${route}`,
    ).toBeVisible();
  }
});

test("T-UX-001 supports keyboard-only activation and visible focus", async ({
  page,
}) => {
  await page.goto("/deals/new?preview=m3");
  const continueButton = page.getByRole("button", { name: "Continue" });
  await tabTo(page, continueButton);
  await expectVisibleKeyboardFocus(continueButton);
  await page.keyboard.press("Enter");
  await expect(page.getByText("Step 2 / 4")).toBeVisible();

  await page.goto("/deals/new?preview=m3");
  const localeButton = page.getByRole("button", { name: "Français" });
  await tabTo(page, localeButton);
  await expectVisibleKeyboardFocus(localeButton);
  await page.keyboard.press("Enter");
  await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  await page.getByRole("button", { name: "Anglais" }).click();
  await expect(page.locator("html")).toHaveAttribute("lang", "en");

  await page.goto(`/people/parties/${partyId}?preview=m3`);
  const identifierReason = page
    .getByLabel("Reason for restricted identifier access *")
    .first();
  await tabTo(page, identifierReason);
  await expectVisibleKeyboardFocus(identifierReason);
  await page.keyboard.type("Customer identity verification");
  const revealIdentifier = page.getByRole("button", {
    name: "Reveal restricted identifier",
  });
  await tabTo(page, revealIdentifier);
  await expectVisibleKeyboardFocus(revealIdentifier);
  await page.keyboard.press("Enter");
  await expect(
    page.getByRole("status").filter({ hasText: "PREVIEW-IDENTIFIER-0141" }),
  ).toContainText("PREVIEW-IDENTIFIER-0141");
});

test("T-UX-001 keeps phone workflow controls at least 44 CSS pixels", async ({
  page,
}) => {
  await page.setViewportSize({ height: 900, width: 360 });
  for (const route of previewRoutes) {
    await page.goto(route);
    const undersized = await page
      .locator(
        'button, summary, a[href], input:not([type="hidden"]), select, textarea',
      )
      .evaluateAll((elements) =>
        elements.flatMap((element) => {
          const root = element.getRootNode();
          if (
            root instanceof ShadowRoot &&
            root.host.localName === "nextjs-portal"
          ) {
            return [];
          }
          const effectiveTarget =
            element instanceof HTMLInputElement &&
            (element.type === "checkbox" || element.type === "radio")
              ? (element.closest("label") ?? element)
              : element;
          const rect = effectiveTarget.getBoundingClientRect();
          const style = window.getComputedStyle(effectiveTarget);
          if (
            style.display === "none" ||
            style.visibility === "hidden" ||
            rect.width === 0 ||
            rect.height === 0
          ) {
            return [];
          }
          return rect.width < 44 || rect.height < 44
            ? [
                {
                  height: Math.round(rect.height),
                  label:
                    element.getAttribute("aria-label") ??
                    effectiveTarget.textContent?.trim().slice(0, 80) ??
                    element.tagName,
                  tag: element.tagName,
                  width: Math.round(rect.width),
                },
              ]
            : [];
        }),
      );
    expect(undersized, `undersized controls at ${route}`).toEqual([]);
  }
});

test("T-UX-002 removes M3 spatial transitions when requested", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto(`/deals/${dealId}/payments?preview=m3`);
  const recordButton = page.getByRole("button", { name: "Record transaction" });
  await expect(recordButton).toBeVisible();
  await expect
    .poll(async () =>
      recordButton.evaluate((element) => {
        const style = window.getComputedStyle(element);
        return {
          animationName: style.animationName,
          transitionDuration: style.transitionDuration,
          transitionProperty: style.transitionProperty,
        };
      }),
    )
    .toEqual({
      animationName: "none",
      transitionDuration: "0s",
      transitionProperty: "opacity",
    });
});

test("T-UX-002 has no automatically detectable accessibility violations", async ({
  page,
}) => {
  await page.setViewportSize({ height: 900, width: 360 });
  for (const route of previewRoutes) {
    await page.goto(route);
    await expect(page.locator("main")).toBeVisible();
    for (let index = 0; index < 50; index += 1) {
      const closedDisclosure = page
        .locator("details:not([open]) > summary:visible")
        .first();
      if ((await closedDisclosure.count()) === 0) break;
      await closedDisclosure.click();
    }
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations, `accessibility violations at ${route}`).toEqual(
      [],
    );
  }
});
