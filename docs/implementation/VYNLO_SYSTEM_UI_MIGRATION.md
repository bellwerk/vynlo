<!-- Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4 -->

# Vynlo System UI migration evidence

- Status: complete; local acceptance verified
- Evidence date: 2026-07-17
- Change class: presentation refactor
- Requirements: `UI-MIG-01` through `UI-MIG-06`

This is the implementation and acceptance record for replacing the
milestone-specific visual system with one shadcn/ui-based Vynlo System.
Hallmark supplied the modern-minimal design discipline: one locked system,
semantic tokens, complete interaction states, restrained motion, and explicit
mobile and anti-slop verification.

The migration did not change a database schema, API contract, RLS policy,
authorization rule, application service, outbox/job contract, audit event, or
business-domain type.

## Starting baseline and evidence limitation

The approved migration brief recorded this starting inventory:

| Surface           | Starting evidence                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------------- |
| Routes            | 25 `page.tsx` routes across public/system, Inventory, People, Deals, Documents, Configuration, and Exports |
| Raw controls      | 343: 227 `input`, 52 `select`, 42 `textarea`, and 22 `button` elements                                     |
| Shared primitives | `Button` was the only shared interactive primitive                                                         |
| Global CSS        | 4,166 lines combining application and milestone presentation                                               |
| Shells            | Separate root/Inventory, M3, and M4 navigation shells                                                      |
| Preview fixtures  | `preview=inventory`, `preview=m3`, and `preview=m4` development data                                       |

The route inventory covered:

- Public and system: `/`, `/login`, `/health`, `/operations`.
- Inventory: `/inventory`, `/inventory/new`, `/inventory/[id]`, and
  `/inventory/[id]/media`.
- People: `/people`, `/people/leads/new`, `/people/leads/[id]`,
  `/people/parties`, `/people/parties/[id]`, `/people/tasks`, and
  `/people/appointments`.
- Deals: `/deals`, `/deals/new`, `/deals/[id]`, `/deals/[id]/trade-ins`,
  `/deals/[id]/finance`, and `/deals/[id]/payments`.
- Documents and configuration: `/documents`, `/documents/[id]`,
  `/configuration`, and `/exports`.

### Historical screenshot exception

There is no committed pre-migration source state for every M3/M4 route and
workbench represented by this change. The migration began in an already changed
worktree, and some of those route files were not present in repository `HEAD`.
Consequently, a deterministic retroactive “before” render cannot be produced or
reviewed without reconstructing and inventing historical UI evidence.

The ten checked-in images are approved post-migration baselines, not mislabeled
before/after pairs. `AC-UI-MIG-01-B` therefore closes with this explicit evidence
exception and a forward-looking comparison suite. The behavioral baseline is
preserved through the existing route tests, preview fixtures, localization,
authorization, PWA, and workspace-isolation tests.

## Requirement and acceptance traceability

| Requirement                            | Implemented evidence                                                                                                                                                                    | Acceptance result                                                                                                                                                                         |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `UI-MIG-01` Audit and baseline         | Route/control/CSS/shell inventory above; existing behavioral suites; ten deterministic forward baselines                                                                                | Complete with the documented historical-screenshot exception                                                                                                                              |
| `UI-MIG-02` Locked design system       | Root [`design.md`](../../design.md), canonical CSS/DTCG/TypeScript tokens, `ThemeMode`, `next-themes`, media-qualified viewport colors, PWA fallback color, and `/dev/design-system`    | Verified by token tests, theme persistence test, gallery coverage, axe, motion, and visual comparisons                                                                                    |
| `UI-MIG-03` Shared shadcn primitives   | 31 reviewed source components in `packages/ui-web`—the 29 requested additions, the existing Button, and supporting Separator—with direct Radix ownership confined there                 | Verified by typecheck, zero-debt policy check, gallery state coverage, keyboard, focus, dialog, and Sheet tests                                                                           |
| `UI-MIG-04` Unified shell              | One permission-aware `OperatorShell`, typed navigation model, desktop sidebar, four mobile tabs, More Sheet, truthful account/connectivity/attention state, and optional save/job slots | Verified by explicit 320–1280 px matrix, touch, skip link, focus trap/restore, safe query, permission, locale, and workspace-remount tests                                                |
| `UI-MIG-05` Route migration            | Documents/Configuration/Exports pilot; Inventory list/intake/detail/media; People/CRM and Deals; Operations/Login/Health/public surfaces                                                | Complete: application source has zero prohibited raw controls and all workbenches consume the shared shell/primitives                                                                     |
| `UI-MIG-06` Enforcement and retirement | Permanent zero-debt checker, six checker tests, CI wiring, legacy shell removal, semantic global foundation, and checked-in browser evidence                                            | Complete: policy check reports zero findings; contextual arbitrary layout values remain a design-review rule because static analysis cannot infer whether an arbitrary value is explained |

## Implemented Vynlo System

### Tokens, theme, and PWA

- `packages/design-tokens/src/tokens.css` is the canonical runtime source for
  light/dark color roles, typography, four-point spacing, radii, shadows, focus,
  44 px targets, motion, charts, sidebar, and z-index.
- `tokens.json` is the portable DTCG representation. `index.ts` exports token
  names and CSS-variable references without copying color values into
  TypeScript.
- `ThemeMode` is `system | light | dark`. `next-themes` defaults to system,
  persists locally under `vynlo-theme`, and applies the resolved class without a
  hydration flash.
- The web viewport emits light and dark `theme-color` values. The manifest uses
  the light system background as the standards-compatible install/launch
  fallback; the media-qualified viewport metadata controls browser chrome for
  both operating-system modes.
- `/dev/design-system` is disabled in production and demonstrates tokens,
  themes, primitives, and default/hover/focus/active/disabled/loading/error/
  success states with English/French copy.

### Shared primitive package

`@vynlo/ui-web` now owns:

- Forms: Field, Label, Input, Textarea, NativeSelect, Select, Checkbox,
  RadioGroup, and Switch.
- Feedback: Alert, Badge, Skeleton, Progress, Sonner, and Tooltip.
- Overlays: Dialog, AlertDialog, Sheet, Drawer, Popover, and DropdownMenu.
- Navigation/data: Tabs, Sidebar, Breadcrumb, Table, Pagination, ScrollArea,
  Command, and Combobox.
- Supporting source: Button and Separator.

The existing `new-york`, Radix-backed, Tailwind v4 monorepo configuration is
retained. shadcn generation runs from `apps/web`; `components.json` routes
shared source into `packages/ui-web`.

### Shared shell and compositions

The typed navigation model carries route, translation key, icon key, immutable
permission key, mobile priority, and mobile placement. Explicit grants are
authoritative, preview fixtures receive only the declared module grants, and
the shell hides protected destinations while permission resolution is pending.
Server/API authorization remains authoritative for direct navigation.

Desktop shows every permitted destination. Mobile keeps Inventory, People,
Deals, and Documents as primary tabs and places Configuration, Exports, and
System in a bottom Sheet. The shell preserves an allowlist of safe query state,
transforms preview context for the target module, and discards secret/unsafe
parameters.

M3 and M4 adapters delegate to the same shell. Workspace changes invalidate
superseded loads and remount workspace-owned content before displaying the new
workspace. Header status comes from real authentication/preview and connectivity
state; save and job content is rendered only when a route supplies it.

Application compositions under `apps/web/components/vynlo-system` include
PageHeader, ResponsiveDataView, MoneyInput, EntityCombobox, StatusBadge,
EmptyState, ErrorState, SaveState, JobStatus, and
ConfirmDestructiveAction. Their props remain business-neutral; workflows and
business decisions remain outside React presentation.

### Route slices

1. Documents, Configuration, and Exports established the bounded pilot.
2. Inventory list, intake, detail/operations, and media adopted the system.
3. People/CRM and Deals adopted the system.
4. Operations, Login, Health, and the public surface adopted the shared theme
   and primitives.

Development preview fixtures remain synthetic and disabled in production:

- Inventory: `?preview=inventory`.
- People/CRM and Deals: `?preview=m3`.
- Documents, Configuration, and Exports: `?preview=m4`.

## Verified local acceptance evidence

| Gate                                                      | Result on 2026-07-17                                                                                                            |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `pnpm check:ui-system`                                    | Passed with 0 prohibited findings and a permanent zero allowance                                                                |
| `pnpm test:ui-system`                                     | Passed 6/6 checker tests                                                                                                        |
| `pnpm typecheck`                                          | Passed; 23 of 24 workspace projects had executable typecheck tasks and all 23 succeeded                                         |
| `pnpm test`                                               | Passed 858/858 tests across 120 files                                                                                           |
| `pnpm lint`                                               | Passed                                                                                                                          |
| `pnpm format:check`                                       | Passed                                                                                                                          |
| Existing contract and security gates                     | Spec, OpenAPI, Markdown, package boundaries, secret scan, Supabase foundation, and high-severity dependency audit all passed    |
| Vynlo System Playwright contract excluding visual capture | Passed 21 tests with 12 intentional project-scope skips                                                                         |
| Responsive matrix                                         | Passed all five representative workflows at 320, 375, 414, 768, and 1280 px                                                     |
| Axe                                                       | No serious or critical violations across representative routes in light/dark and English/French, including an open mobile Sheet |
| Deterministic visual comparison                           | Ten baselines generated and a clean comparison passed with the 1% maximum pixel-difference policy                               |
| Full repository Playwright suite                          | Passed: 210 discovered, 196 passed, 14 intentional project-scope skips, 0 failures (2.2 minutes)                                |
| Production build                                          | Passed: worker TypeScript/bundle; Next.js 16.2.10 compile and TypeScript; 54/54 static pages; route manifest completed          |

Intentional Playwright skips prevent duplicate work across device projects: the
desktop project drives explicit viewport, axe, and visual matrices; the mobile
project supplies real coarse-pointer/touch emulation.

## Visual evidence

The approved forward baselines live in
`tests/e2e/vynlo-system-ui.spec.ts-snapshots`:

| Workflow      | 375 px                        | 1440 px                        |
| ------------- | ----------------------------- | ------------------------------ |
| Inventory     | `vynlo-inventory-375.png`     | `vynlo-inventory-1440.png`     |
| Deal detail   | `vynlo-deal-detail-375.png`   | `vynlo-deal-detail-1440.png`   |
| Documents     | `vynlo-documents-375.png`     | `vynlo-documents-1440.png`     |
| Configuration | `vynlo-configuration-375.png` | `vynlo-configuration-1440.png` |
| Exports       | `vynlo-exports-375.png`       | `vynlo-exports-1440.png`       |

Capture preparation fixes locale, theme, timezone, fonts, images, time, caret,
animation, and transition state. Synthetic fixtures provide deterministic ready
markers. A visual baseline changes only with an approved presentation change;
it is never regenerated merely to make CI green.

## Accessibility, localization, and isolation evidence

- The shared shell is tested at 320, 375, 414, 768, and 1280 px, with no
  horizontal page overflow and `overflow-x: clip` on root/body.
- Phone-visible controls and open-Sheet controls are checked for an effective
  44 × 44 px target. Navigation labels remain unambiguous and one line.
- The More Sheet traps focus, closes on Escape, and restores focus. The skip link
  is first in keyboard order, visibly focused, and moves focus to main content.
- Reduced motion removes spatial transitions and caps remaining motion at
  150 ms. Normal overlay motion is limited to opacity/transform for 120–220 ms.
- Locale changes preserve the path, entity identifier, workspace, and safe query
  context. Unsafe access tokens are removed, and preview context is transformed
  when crossing module boundaries.
- Workspace-switch tests assert that M3 and M4 workspace-owned views remount and
  remove a stale-workspace probe before the new view is displayed.
- Axe covers representative list, intake/form, detail, document, report, and
  open-dialog surfaces in both themes and both supported languages.

## Enforcement and CI operation

The repository check enforces a permanent zero allowance for:

- raw lowercase `button`, `input`, `select`, and `textarea` JSX in `apps/web`;
- direct Radix imports outside `packages/ui-web/src`;
- raw/palette-specific colors outside canonical token and required metadata
  ownership;
- `transition-all`, color/geometry/filter/shadow transitions, and thick colored
  side stripes;
- milestone shell files that recreate `aside` or `nav` instead of delegating to
  the shared shell.

Reference searches find no `.m3-*` or `.m4-*` selector blocks in the global
stylesheet. Compatibility token aliases that still have active TypeScript/JSX
consumers remain intentionally; they are not dead milestone shells or an
authorization/business compatibility layer.

Arbitrary values such as `minmax(0,1fr)`, token references, and content-specific
maximum widths can be legitimate, so the checker does not reject every bracketed
Tailwind value. `design.md`, code review, responsive tests, and the Hallmark
review decide whether those values are explained and semantic.

Run locally:

```text
pnpm check:ui-system
pnpm test:ui-system
pnpm exec playwright test tests/e2e/vynlo-system-ui.spec.ts
```

The root `verify` script includes the UI policy and checker tests. The quality
workflow installs Chromium, runs the full repository gates and browser suite,
and uploads `playwright-report` plus `test-results` even when a browser test
fails.

## Compatibility and no-business-change record

- No database migration, schema change, seed, or RLS policy was introduced.
- No REST/OpenAPI, application-service, outbox, job, audit-event, or domain-type
  contract changed.
- `organization_id` and `workspace_id` behavior is unchanged. Workspace context
  remains derived and verified from authenticated membership, never trusted
  from arbitrary UI input.
- Theme preference is local presentation state only; it creates no database
  column or domain event.
- Permission-aware navigation is a discoverability aid, not authorization.
- Existing document numbering, immutable configuration versions, calculation,
  export, media, retry, and audit behavior remain owned by the same services.
- English and French remain required. Machine keys, permission keys, record
  identifiers, and persisted values are never translated.
- The system is tenant-neutral. No tenant-specific copy, palette, route,
  fixture, formula, or component branch was added.

## Contribution and rollback references

- Theme, state, navigation, responsive, and prohibited-pattern contract:
  [`design.md`](../../design.md).
- Token contribution workflow:
  [`packages/design-tokens/README.md`](../../packages/design-tokens/README.md).
- Shared primitive contribution workflow:
  [`packages/ui-web/README.md`](../../packages/ui-web/README.md).
- Application composition, navigation, responsive, and preview workflow:
  [`apps/web/components/README.md`](../../apps/web/components/README.md).

Rollback remains presentation-slice based. Revert the failing route/shell/
component presentation change and restore its last-known-good styling import;
do not roll back data or rewrite history because this migration contains no data
change. Authorization, tenant isolation, localization, audit, and workflow tests
must still pass after a rollback.
