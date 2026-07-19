# Web application components

Application-aware compositions, the shared authenticated shell, and route
workbenches belong here. Reusable shadcn registry primitives are routed by
`apps/web/components.json` to `packages/ui-web/src/components`.

## Ownership boundary

- `@vynlo/ui-web` owns business-neutral primitives and direct Radix imports.
- `components/vynlo-system` owns reusable application compositions such as
  PageHeader, ResponsiveDataView, MoneyInput, EntityCombobox, StatusBadge,
  EmptyState, ErrorState, SaveState, JobStatus, and destructive confirmation.
- `operator-shell.tsx` owns authenticated navigation chrome and consumes the
  typed model in `apps/web/lib/navigation.ts`.
- Route workbenches own translated copy and presentation orchestration. Business
  rules, permission enforcement, application services, audit behavior, durable
  jobs, and workspace isolation remain in their existing application/server
  layers.

Do not create another milestone, module, or tenant shell. The M3 and M4 runtime
adapters delegate to the same `OperatorShell` and key workspace-owned content so
a workspace change remounts the view before new data is shown.

## Adding or changing navigation

1. Add the destination to the typed `operatorNavigation` model with its route,
   translation key, icon key, immutable permission key, mobile priority, and
   `primary | more` placement.
2. Add English and French labels. The mobile contract keeps Inventory, People,
   Deals, and Documents as primary destinations; lower-priority destinations
   belong in the Sheet-based More surface unless the product contract changes.
3. Preserve only allowlisted query context. Preview context is transformed for
   the destination module and secret/unsafe parameters are discarded.
4. Test permission filtering, direct-route authorization, `aria-current`,
   locale/path/entity preservation, keyboard focus, and the 44 px mobile target.

Navigation filtering controls discoverability only. It never replaces the
existing API and server-side authorization checks.

## Adding or changing application state

- Compose shared primitives instead of raw interactive elements. Forms use
  Field, Label, control, description, and associated error text.
- Supply translated idle, loading, success, empty, error, offline, processing,
  stale, and retry copy when the workflow can reach those states.
- Use SaveState and JobStatus for persistent operational feedback. Do not render
  placeholder account, search, save, job, or connectivity actions.
- Keep state transitions in the current application service or runtime. A React
  component may present or request a transition; it must not reimplement the
  business rule.

## Responsive contribution pattern

- Start at 320 px and verify 320, 375, 414, 768, and 1280 px.
- Use ResponsiveDataView or an equivalent composition to render phone-usable
  cards/lists and productive desktop tables. A table may not be the only core
  workflow.
- Use `minmax(0, 1fr)` for content-bearing grid tracks, keep long identifiers
  wrappable, and avoid horizontal page overflow. A local scroll area must be
  explicit and labeled.
- Verify coarse pointer, 44 px targets, safe-area clearance, visible actions,
  keyboard equivalence, and longer French copy.
- Update a 375 px or 1440 px visual baseline only for an approved presentation
  change.

## Migrated workbenches and preview fixtures

- Inventory list, intake, detail/operations, and media use
  `?preview=inventory` in development.
- People/CRM and Deals use `?preview=m3` in development.
- Documents, Configuration, and Exports use `?preview=m4` in development.
- Preview switches are disabled in production and use synthetic data only.

The Documents flow retains type availability, schema validation, unnumbered
preview, explicit number allocation, immutable render/file history, signing,
void, and supersession (`M4-DOC-AC-001..010`, `M4-NUM-AC-002..005`).
Configuration retains immutable version/checksum and append-only approval
behavior (`M4-CFG-AC-001..005`, `M4-CALC-AC-005`, `M4-TAX-AC-003..005`).
Exports retain phone-readable inventory, lead, and deal reports and
deterministic CSV/XLSX jobs (`M4-EXP-AC-001..005`).

Route-specific browser journeys remain in their existing Playwright files. The
cross-system contract—theme, shell, responsive behavior, localization,
workspace remounting, accessibility, and screenshots—lives in
`tests/e2e/vynlo-system-ui.spec.ts`.
