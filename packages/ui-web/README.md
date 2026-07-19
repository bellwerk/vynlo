# @vynlo/ui-web

Reviewed shadcn/ui source components shared by Vynlo web applications. This
package is an ownership boundary inside the modular monolith, not an
independently deployed service or a second component framework.

Shared primitives consume Vynlo semantic tokens and preserve the 44 px target,
focus, keyboard, screen-reader, localization, and status contracts in
`design.md`. Permission checks, workflow transitions, data fetching, and domain
rules do not belong here.

## Public surface

The package contains the requested shadcn foundation plus `Separator`:

- Forms: Field, Label, Input, Textarea, NativeSelect, Select, Checkbox,
  RadioGroup, Switch.
- Feedback: Alert, Badge, Skeleton, Progress, Sonner, Tooltip.
- Overlays: Dialog, AlertDialog, Sheet, Drawer, Popover, DropdownMenu.
- Navigation and data: Tabs, Sidebar, Breadcrumb, Table, Pagination,
  ScrollArea, Command, Combobox, Separator.

Prefer explicit subpath imports such as
`@vynlo/ui-web/components/button`. The package root export remains available
for compatibility and exposes the same reviewed surface.

## Source layout

- `src/components`: shared shadcn/ui source components.
- `src/lib/control-status.ts`: shared async/validation presentation status.
- `src/lib/utils.ts`: the standard `cn` class-composition utility.
- `src/hooks`: shared web-only hooks required by reviewed primitives.
- `src/index.ts`: public exports; a new primitive is not public until exported.

Direct Radix imports are allowed only under this package. Application code
imports the Vynlo wrapper so tokens, accessibility fixes, and API compatibility
remain centralized.

## Adding a shadcn primitive

1. Run the shadcn generator from `apps/web`. Do not re-run initialization.
   `apps/web/components.json` keeps the existing `new-york`, Radix, Tailwind v4
   configuration and routes registry UI source into this package.
2. Review the generated diff. Keep DOM/Radix details here, use semantic token
   utilities, remove palette literals and `transition-all`, and preserve public
   refs and ARIA behavior.
3. Normalize controls to a minimum 44 px effective target and the Vynlo control,
   panel, or overlay radius. Motion may use opacity/transform for 120–220 ms
   only, with reduced-motion handling.
4. Export the primitive from `src/index.ts`. Keep its props business-neutral and
   preserve the upstream accessibility contract rather than wrapping it in a
   route-specific API.
5. Add it to the non-production `/dev/design-system` gallery in light and dark.
   Demonstrate default, hover, focus-visible, active, disabled, loading, error,
   and success where the component can express those states.
6. Add component/type tests for behavior that is not already guaranteed by the
   underlying primitive. Verify keyboard operation, focus restoration, Escape,
   and localized labels when applicable.

## Modifying an existing primitive

- Treat prop and subpath exports as compatibility surfaces. Prefer additive
  changes and update every application caller before removing an export.
- Use `ControlStatus` when a control can express loading, error, or success.
  Callers still supply translated status copy and Field-based description/error
  text; color is never the only signal.
- Use NativeSelect for short fixed lists. Use Select or Combobox for discoverable
  or searchable entities. Keep native date fields unless a calendar workflow is
  genuinely required.
- Do not import application translation dictionaries into this package. Accept
  accessible/localized labels as props or compose them in `apps/web`.
- Do not place immutable permission keys, workspace decisions, money rules, or
  API calls in a primitive.

Run at minimum:

```text
pnpm --filter @vynlo/ui-web typecheck
pnpm check:ui-system
pnpm test:ui-system
pnpm test
```

For visible or interactive changes, also run the Vynlo System Playwright suite
covering keyboard, touch, 320–1280 px layouts, both themes and languages, axe,
reduced motion, and deterministic screenshots.
