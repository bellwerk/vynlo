<!-- Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4 -->

# Design — Vynlo System

A locked design system for the Vynlo application. Every page and component
reads this contract before introducing presentation code. Extend this file when
the system needs to grow; do not create per-route or per-tenant themes.

## Product intent

Vynlo is an operational dealership workspace for people who work in the product
throughout the day. The interface is clean, exact, calm, and lightly layered. It
borrows the restraint and craft of iOS without copying Apple assets or native-app
chrome. Information density should support fast work while remaining usable by
touch at 320–414 px.

## Genre and voice

- Genre: modern-minimal.
- Application macrostructure: Workbench — persistent navigation, compact chrome,
  clear page header, and one task-focused main canvas.
- Public and authentication pages: restrained long-document or focused-form
  compositions using the same typography, colors, geometry, and controls.
- Voice: concise, factual, and reassuring. Labels name the object or action;
  status text says what happened and what the user can do next.
- Enrichment: none inside the application. Function, hierarchy, and real data
  carry the interface.

## Theme

The canonical values live in
`packages/design-tokens/src/tokens.css`. Application CSS consumes semantic
variables and must not duplicate their color values.

`ThemeMode` is `system | light | dark`. The web application persists the local
choice under `vynlo-theme`; no database preference is created. `system` is the
default, and `next-themes` applies the resolved class before hydration so the
first painted theme matches the operating-system preference.

- Light foundation: `#F5F5F7`-equivalent cool-neutral background, white surface,
  near-black foreground, accessible system blue for actions.
- Dark foundation: `#0B0B0C`-equivalent background, `#1C1C1E`-equivalent surface,
  off-white foreground, lighter accessible blue for actions.
- Semantic roles: background, foreground, card, popover, primary, secondary,
  muted, accent, destructive, success, warning, border, input, ring, chart, and
  sidebar.
- Accent placement stays below roughly five percent of a viewport. Accent is for
  actions, selection, focus, and links—not decoration.
- Translucency and backdrop blur are limited to navigation chrome, sheets,
  dialogs, menus, and temporary overlays.

## Typography

- Display and body: `-apple-system`, `BlinkMacSystemFont`, `SF Pro Text`,
  `Segoe UI Variable`, `Segoe UI`, sans-serif. No proprietary font is bundled.
- Mono: native UI monospace stack for identifiers, VINs, checksums, and technical
  values only.
- Headings use the same family with weight and spacing for hierarchy. No serif,
  novelty, or oversized editorial headings inside the application.
- Body copy targets 45–75 characters per line. Uppercase is reserved for brief
  metadata labels and never used for paragraphs or primary actions.

## Geometry and spacing

- Four-point spacing grid. Prefer the named `--space-*` variables.
- Minimum interactive target: 44 × 44 px, including icon-only actions.
- Controls: 10 px radius. Panels: 14–16 px radius. Dialogs and sheets: 20 px
  radius. Pills are reserved for status, filters, and compact toggles.
- Surfaces use subtle separators first and `--shadow-whisper` only when elevation
  clarifies hierarchy. Temporary overlays use `--shadow-overlay`.
- Page content has a readable maximum width; operational tables may use the full
  workbench canvas.

## Shared shell

- All authenticated routes use one permission-aware `OperatorShell`/`AppShell`.
- Desktop: visible left sidebar with every permitted destination and a compact
  sticky header.
- Mobile: Inventory, People, Deals, and Documents are primary bottom tabs.
  Configuration, Exports, and System live in the Sheet-based More destination.
- Header controls are workspace, locale, theme, account/save/job state when
  available, and offline status. Do not render placeholder search or dead actions.
- Navigation carries an immutable permission key. API authorization remains the
  enforcement boundary.
- Route changes preserve locale and approved preview/query context. Workspace
  changes remount workspace-owned state and ignore stale responses.

## Components and ownership

- `@vynlo/ui-web` owns reviewed shadcn source components and business-neutral
  primitives. Direct Radix imports are allowed only there.
- `apps/web` owns permission checks, application navigation, workflows, and
  domain-aware compositions such as money, entity, save, job, and status views.
- Forms use Field + Label + control + description/error structure. NativeSelect
  is for short fixed lists; Select or Combobox is for discoverable/searchable
  entities; dates remain native unless the workflow needs a calendar.
- Mobile operational data uses cards/lists; desktop may switch to tables.
- Every asynchronous workflow exposes idle, pending, success, empty, error, and
  retry states. Uploads additionally expose progress and processing.
- The non-production `/dev/design-system` gallery is the executable catalogue
  for primitives, semantic tokens, themes, and interaction states. A shared
  primitive is incomplete until its public states appear there.

## State matrix

Every interactive primitive and composition must define and demonstrate:

| State           | Requirement                                                               |
| --------------- | ------------------------------------------------------------------------- |
| Default         | Clear affordance and readable semantic contrast.                          |
| Hover           | Color or separator change only; no layout movement.                       |
| Focus visible   | 3 px system-blue ring with offset; never suppressed.                      |
| Active/selected | Semantic accent plus non-color indication.                                |
| Disabled        | Non-interactive, visibly unavailable, still legible.                      |
| Loading/pending | `aria-busy`, stable dimensions, and progress or concise text.             |
| Error           | Inline reason, recovery action, and destructive semantics where relevant. |
| Success         | Concise confirmation without celebratory or blocking animation.           |

Empty, offline, stale, and partial-data states are required where the workflow
can produce them. A blank panel is never an acceptable state.

## Responsive behavior

- Test widths: 320, 375, 414, 768, and 1280 px; reference screenshots at 375
  and 1440 px.
- Start with the phone layout. Enhance at available-space breakpoints rather than
  targeting device names.
- No horizontal page overflow. Wide data structures get responsive cards or an
  explicitly labeled local scroll region.
- Touch/coarse-pointer users receive 44 px targets, visible actions, and no
  hover-only disclosure. Focus and keyboard flows remain equivalent.
- The mobile bottom navigation respects safe-area insets and never obscures the
  final form control or action.

## Motion and microinteractions

- Transitions last 120–220 ms and animate opacity or transform only.
- Success is quiet: persistent status text or a short toast. Destructive actions
  require an explicit confirmation surface and restore focus on close.
- Tooltips supplement icon labels; they never contain required instructions.
- `prefers-reduced-motion` removes spatial movement and limits remaining fades to
  150 ms or less.
- Never use `transition-all`, bounce, spring, confetti, cursor effects, ambient
  motion, or decorative parallax.

## Accessibility and localization

- Target WCAG 2.2 AA in both themes and English/French.
- Every control has a programmatic name; errors are associated with their field;
  dialogs trap and restore focus; Escape closes temporary overlays.
- Preserve skip links, visible focus, `aria-current`, live save/job status, and
  logical heading order.
- UI copy uses translation keys. Validate the longer French layout at every
  responsive width; truncation may not hide required information.
- Never use color alone to communicate state.

## Prohibited patterns

- Tenant-specific visual forks, milestone-specific shells, or page-local themes.
- Neon lime, rust, warm-paper, serif-display, square-control, or glass-card drift.
- Raw color literals, unexplained arbitrary Tailwind values, local shadow/radius
  inventions, or direct Radix imports in application code.
- Raw `button`, `input`, `select`, or `textarea` elements outside approved shared
  component source, except narrowly documented platform necessities.
- Decorative card grids, excessive pills, nested floating containers, fake
  search, dead actions, hover-only controls, and icon-only controls without names.

## Quality and change protocol

### Add or modify a token

1. Name the semantic role before choosing a value. Do not name a token after a
   route, tenant, milestone, or one visual sample.
2. Change the light and dark values in
   `packages/design-tokens/src/tokens.css`. This is the only runtime value
   source.
3. Mirror the portable value in `tokens.json`. Export only token names and CSS
   variable references from `index.ts`; never copy color values into TypeScript.
4. Add or update contrast, invariant, and type tests. Exercise the token in the
   development gallery in both themes.

See `packages/design-tokens/README.md` for the package-level checklist.

### Add or modify a shared primitive

1. Run the shadcn generator from `apps/web`; its `components.json` alias routes
   reviewed source into `packages/ui-web/src/components`.
2. Keep Radix imports and DOM implementation details inside `@vynlo/ui-web`.
   Application code imports the Vynlo wrapper.
3. Use semantic tokens, preserve ref/ARIA behavior, keep a 44 px target, and
   implement default, hover, focus-visible, active, disabled, loading, error,
   and success behavior where the control can express those states.
4. Export the component, document its localized status contract, add it to the
   gallery, and run type, policy, keyboard, accessibility, and responsive gates.

See `packages/ui-web/README.md` for ownership and review rules.

### Add or modify application state

- Business-neutral visual state belongs in an app composition; the workflow
  transition and permission decision remain in the existing application layer.
- Supply localized pending, success, empty, error, offline, stale, processing,
  and retry copy as applicable. Use live regions only for meaningful state
  changes and keep layout dimensions stable while pending.
- Add failure and recovery assertions, not only a happy-path screenshot.

### Add or modify navigation

- Update the typed model in `apps/web/lib/navigation.ts` with the route,
  translation key, icon key, immutable permission key, mobile priority, and
  `primary | more` placement.
- Add English and French labels, then verify desktop/sidebar and mobile/Sheet
  discovery. Navigation filtering improves discoverability; API authorization
  remains authoritative.
- Test `aria-current`, locale and safe-query preservation, hidden destinations,
  keyboard focus, and the 44 px mobile target contract.

### Add or modify a responsive pattern

- Start at 320 px. Prefer `ResponsiveDataView` for mobile-card/desktop-table
  data and `minmax(0, 1fr)` for content-bearing grid tracks.
- Verify 320, 375, 414, 768, and 1280 px, coarse pointer, no horizontal page
  overflow, one-line action labels, safe-area clearance, and French expansion.
- Add or update the deterministic 375 px and 1440 px baseline only for an
  approved visual change.

### Required gates

- Each migrated slice keeps APIs, application services, audit behavior,
  authorization, workspace isolation, and business rules unchanged.
- Run unit/component/integration/localization/authorization tests, axe in both
  themes and languages, keyboard and touch checks, responsive screenshots,
  reduced motion, and `pnpm check:ui-system` plus `pnpm test:ui-system`.

## Exports

- CSS and shadcn variables: `packages/design-tokens/src/tokens.css`.
- DTCG tokens: `packages/design-tokens/src/tokens.json`.
- TypeScript token names and CSS-variable references:
  `packages/design-tokens/src/index.ts`.
- Convenience CSS entry point: `tokens.css` at the repository root.
